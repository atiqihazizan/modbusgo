import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import './mqtt_topics.dart';

// Offline queue — simpan penghantaran berstruktur (sama online/offline):
//   • backfill batch → array ke /backfill
//   • bundle         → single ke /bundle
// Flush ikut susunan asal bila reconnect.

enum _OfflineDeliveryKind { backfillBatch, bundle }

class _OfflineDelivery {
  _OfflineDelivery.backfill(this.items, this.enqueuedAtMs)
      : kind = _OfflineDeliveryKind.backfillBatch,
        bundle = null;

  _OfflineDelivery.bundle(this.bundle, this.enqueuedAtMs)
      : kind = _OfflineDeliveryKind.bundle,
        items = null;

  final _OfflineDeliveryKind kind;
  final List<Map<String, dynamic>>? items;
  final Map<String, dynamic>? bundle;
  final int enqueuedAtMs;

  int get itemCount =>
      kind == _OfflineDeliveryKind.backfillBatch ? items!.length : 1;
}

class MqttOfflineQueue {
  MqttOfflineQueue._internal();
  static final MqttOfflineQueue _instance = MqttOfflineQueue._internal();
  factory MqttOfflineQueue() => _instance;

  static const int _maxItems = 1000;
  static const int _ttlMs = 24 * 60 * 60 * 1000; // 24 jam

  final List<_OfflineDelivery> _deliveries = [];
  bool _flushing = false;

  /// Jumlah bundle/item menunggu (backfill items + bundle count).
  int get length =>
      _deliveries.fold<int>(0, (sum, d) => sum + d.itemCount);

  bool get isEmpty => _deliveries.isEmpty;

  void _pruneExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _deliveries.removeWhere((d) => now - d.enqueuedAtMs > _ttlMs);
  }

  void _trimOverflow() {
    while (_lengthItems() > _maxItems && _deliveries.isNotEmpty) {
      _deliveries.removeAt(0);
    }
  }

  int _lengthItems() =>
      _deliveries.fold<int>(0, (sum, d) => sum + d.itemCount);

  /// Simpan batch backfill (array) — sama struktur online.
  void enqueueBackfillBatch(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _pruneExpired();
    _deliveries.add(
      _OfflineDelivery.backfill(
        items.map((e) => Map<String, dynamic>.from(e)).toList(),
        now,
      ),
    );
    _trimOverflow();
  }

  /// Simpan single bundle (current) — sama struktur online.
  void enqueueBundle(Map<String, dynamic> data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pruneExpired();
    _deliveries.add(
      _OfflineDelivery.bundle(Map<String, dynamic>.from(data), now),
    );
    _trimOverflow();
  }

  /// Flush semua penghantaran tertunda ikut susunan & topik asal.
  Future<int> flush(MqttServerClient client, String deviceId) async {
    if (_flushing || _deliveries.isEmpty) return 0;
    _flushing = true;
    try {
      _pruneExpired();
      if (_deliveries.isEmpty) return 0;

      var sent = 0;
      final topics = MqttTopics(deviceId);

      for (final delivery in List<_OfflineDelivery>.from(_deliveries)) {
        if (delivery.kind == _OfflineDeliveryKind.backfillBatch) {
          final items = delivery.items!;
          if (items.isEmpty) continue;
          final ok = _publishRaw(
            client,
            topics.backfill,
            jsonEncode(items),
          );
          if (ok) {
            sent += items.length;
            if (kDebugMode) {
              debugPrint(
                '📤 [MQTT] Backfill flushed batch (${items.length} items)',
              );
            }
          }
        } else {
          final bundle = delivery.bundle!;
          final ok = _publishRaw(
            client,
            topics.bundle,
            jsonEncode(bundle),
          );
          if (ok) {
            sent += 1;
            if (kDebugMode) debugPrint('📤 [MQTT] Bundle flushed (current)');
          }
        }
      }

      _deliveries.clear();
      if (kDebugMode && sent > 0) {
        debugPrint('📤 [MQTT] Offline queue flushed ($sent items total)');
      }
      return sent;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Offline flush error: $e');
      return 0;
    } finally {
      _flushing = false;
    }
  }

  bool _publishRaw(MqttServerClient client, String topic, String payload) {
    try {
      final builder = MqttClientPayloadBuilder()..addString(payload);
      client.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Flush publish error: $e');
      return false;
    }
  }

  void clear() => _deliveries.clear();
}
