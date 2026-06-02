import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import './mqtt_topics.dart';

// Offline queue — simpan bundle bila MQTT putus; flush ke /backfill bila sambung balik.
// Ada TTL: buang item terlalu lama supaya backend tak banjir data basi.

class _QueuedItem {
  _QueuedItem(this.data, this.enqueuedAtMs);
  final Map<String, dynamic> data;
  final int enqueuedAtMs;
}

class MqttOfflineQueue {
  MqttOfflineQueue._internal();
  static final MqttOfflineQueue _instance = MqttOfflineQueue._internal();
  factory MqttOfflineQueue() => _instance;

  static const int _maxSize = 1000;
  static const int _ttlMs = 24 * 60 * 60 * 1000; // 24 jam

  final List<_QueuedItem> _queue = [];
  bool _flushing = false;

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;

  void enqueue(Map<String, dynamic> data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _queue.removeWhere((it) => now - it.enqueuedAtMs > _ttlMs);
    while (_queue.length >= _maxSize) {
      _queue.removeAt(0);
    }
    _queue.add(_QueuedItem(Map<String, dynamic>.from(data), now));
  }

  /// Flush semua item ke topic /backfill sebagai SATU array (backend terima array).
  Future<int> flush(MqttServerClient client, String deviceId) async {
    if (_flushing || _queue.isEmpty) return 0;
    _flushing = true;
    final topic = MqttTopics(deviceId).backfill;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _queue.removeWhere((it) => now - it.enqueuedAtMs > _ttlMs);
      if (_queue.isEmpty) return 0;

      final items = _queue.map((it) => it.data).toList();
      final payload = jsonEncode(items);
      final builder = MqttClientPayloadBuilder()..addString(payload);

      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      final sent = items.length;
      _queue.clear();
      if (kDebugMode) debugPrint('📤 [MQTT] Backfill flushed $sent items');
      return sent;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Backfill flush error: $e');
      return 0;
    } finally {
      _flushing = false;
    }
  }

  void clear() => _queue.clear();
}
