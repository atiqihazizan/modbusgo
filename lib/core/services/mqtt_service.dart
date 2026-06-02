import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import './mqtt_offline_queue.dart';
import './mqtt_topics.dart';
import 'mqtt_offline_queue.dart';
import 'mqtt_topics.dart';

// MqttService — singleton MQTT client untuk publish tracking data ke backend v3.
//
// Broker  : wss://mahsites.net:8887/ws
// Auth    : wsmqtt / w5mqtt
// Topik   : LoRa/tracking/{device_id}/bundle | status | backfill ; subscribe /ack
// Payload : node_id (= device_id) TANPA agency_token. Backend route guna device_id.
//
// Ketahanan: auto-reconnect (backoff 2→60s), offline queue→backfill, LWT.

class MqttService {
  MqttService._internal();
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;

  static const String _host = 'mahsites.net';
  static const int _port = 8887;
  static const String _wsPath = '/ws';
  static const String _username = 'wsmqtt';
  static const String _password = 'w5mqtt';

  MqttServerClient? _client;
  String? _deviceId;
  Timer? _reconnectTimer;
  StreamSubscription? _updatesSub;

  int _backoffSec = 2;
  bool _intentional = false;
  bool _initialized = false;
  bool _paused = false;

  void Function(bool connected)? onConnectionChanged;
  void Function(bool success)? onPublishResult;
  void Function(Map<String, dynamic> ack)? onAck;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  bool get isInitialized => _initialized;
  int get queueLength => MqttOfflineQueue().length;

  void pause() => _paused = true;
  void resume() => _paused = false;

  Future<void> init({required String deviceId}) async {
    if (_initialized && _deviceId == deviceId && isConnected) {
      onConnectionChanged?.call(true);
      return;
    }
    if (_initialized && _deviceId != deviceId) {
      disconnect();
    }
    _deviceId = deviceId;
    _initialized = true;
    _intentional = false;
    await _createAndConnect();
  }

  Future<void> _createAndConnect() async {
    final deviceId = _deviceId!;
    _updatesSub?.cancel();
    _updatesSub = null;
    try {
      _client?.disconnect();
    } catch (_) {}

    final clientId = '${deviceId}_${_nowMs()}';
    final url = 'wss://$_host:$_port$_wsPath';

    final client = MqttServerClient.withPort(url, clientId, _port);
    client.useWebSocket = true;
    // NOTA: JANGAN set client.secure untuk wss — skema wss:// + useWebSocket sudah cukup.
    // client.secure hanya untuk TCP secure, bukan websocket (per doc rasmi mqtt_client).
    client.logging(on: kDebugMode);
    client.keepAlivePeriod = 20;
    client.autoReconnect = false;
    client.connectTimeoutPeriod = 15000;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    final willPayload = jsonEncode({'online': false, 'ts': _nowMs()});
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(_username, _password)
        .withWillTopic(MqttTopics(deviceId).status)
        .withWillMessage(willPayload)
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain()
        .startClean();

    _client = client;

    try {
      if (kDebugMode) debugPrint('🔌 [MQTT] Connecting $url ...');
      await client.connect();
      _backoffSec = 2;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Connect failed: $e');
      onConnectionChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    _intentional = false;
    _backoffSec = 2;
    if (kDebugMode) debugPrint('✅ [MQTT] Connected');
    onConnectionChanged?.call(true);

    _rawPublish(
      MqttTopics(_deviceId!).status,
      jsonEncode({'online': true, 'ts': _nowMs()}),
      retain: true,
      notify: false,
    );

    _client!.subscribe(MqttTopics(_deviceId!).ack, MqttQos.atLeastOnce);

    _updatesSub?.cancel();
    _updatesSub = _client!.updates!.listen(_onMessages);

    if (!MqttOfflineQueue().isEmpty) {
      MqttOfflineQueue().flush(_client!, _deviceId!);
    }
  }

  void _onDisconnected() {
    if (kDebugMode) debugPrint('🔴 [MQTT] Disconnected');
    _updatesSub?.cancel();
    _updatesSub = null;
    onConnectionChanged?.call(false);
    if (!_intentional) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _backoffSec;
    if (kDebugMode) debugPrint('🔄 [MQTT] Reconnect dalam ${delay}s');
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      _backoffSec = (_backoffSec * 2).clamp(2, 60);
      await _createAndConnect();
    });
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final m in messages) {
      final rec = m.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        rec.payload.message,
      );
      if (m.topic == MqttTopics(_deviceId!).ack) {
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          if (kDebugMode) debugPrint('✅ [MQTT] ACK: $data');
          onAck?.call(data);
        } catch (_) {}
      }
    }
  }

  /// Publish bundle tracking. Kalau offline → masuk queue (tak hilang).
  void publishBundle(Map<String, dynamic> data) {
    final payload = _buildPayload(data);
    if (_paused) {
      onPublishResult?.call(false);
      return;
    }
    if (!isConnected) {
      MqttOfflineQueue().enqueue(payload);
      onPublishResult?.call(false);
      if (kDebugMode) {
        debugPrint(
          '📦 [MQTT] Offline — queued (len: ${MqttOfflineQueue().length})',
        );
      }
      return;
    }
    _rawPublish(MqttTopics(_deviceId!).bundle, jsonEncode(payload));
  }

  /// Bina payload padan backend normalizeTrackingData.
  /// node_id WAJIB (= device_id). TANPA agency_token.
  Map<String, dynamic> _buildPayload(Map<String, dynamic> data) {
    return <String, dynamic>{
      'node_id': _deviceId,
      'send_dt': _nowIso(),
      'status_live': 'online',
      ...data,
    };
  }

  void _rawPublish(
    String topic,
    String payload, {
    bool retain = false,
    bool notify = true,
  }) {
    if (!isConnected) {
      if (notify) onPublishResult?.call(false);
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder()..addString(payload);
      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: retain,
      );
      if (notify) onPublishResult?.call(true);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Publish error: $e');
      if (notify) onPublishResult?.call(false);
    }
  }

  void disconnect() {
    _intentional = true;
    _reconnectTimer?.cancel();
    _updatesSub?.cancel();
    _updatesSub = null;
    if (isConnected) {
      _rawPublish(
        MqttTopics(_deviceId!).status,
        jsonEncode({'online': false, 'ts': _nowMs()}),
        retain: true,
        notify: false,
      );
    }
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    _initialized = false;
    onConnectionChanged?.call(false);
    if (kDebugMode) debugPrint('🔌 [MQTT] Disconnected (intentional)');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}
