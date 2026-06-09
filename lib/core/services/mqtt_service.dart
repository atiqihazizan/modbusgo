import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import './mqtt_offline_queue.dart';
import './mqtt_topics.dart';

// MqttService — singleton MQTT client untuk publish tracking data ke backend v3.
//
// Broker  : wss://mahsites.net:8887/ws
// Auth    : wsmqtt / w5mqtt
// Topik   : LoRa/tracking/{device_id}/bundle | status | backfill ; subscribe /ack
// Payload : node_id (= device_id) TANPA agency_token. Backend route guna device_id.
//
// Ketahanan:
//   - Auto-reconnect exponential backoff (2→32s), HAD 5 percubaan.
//   - Habis 5x → onReconnectExhausted (UI toast minta manual reconnect).
//   - manualReconnect() → reset counter, cuba 5x lagi.
//   - resumeReconnect() → dipanggil bila app kembali foreground (jika exhausted).
//   - Offline queue → flush ke /backfill bila reconnect (data tak hilang).
//   - LWT (Last Will): {online:false} bila putus mendadak.

class MqttService {
  MqttService._internal();
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;

  static const String _host = 'mahsites.net';
  static const int _port = 8887;
  static const String _wsPath = '/ws';
  static const String _username = 'wsmqtt';
  static const String _password = 'w5mqtt';

  static const int _maxReconnectAttempts = 5; // had cubaan auto

  MqttServerClient? _client;
  String? _deviceId;
  Timer? _reconnectTimer;
  StreamSubscription? _updatesSub;

  int _backoffSec = 2;
  int _reconnectAttempts = 0; // kira cubaan auto semasa
  bool _exhausted = false; // true bila 5x gagal
  bool _intentional = false;
  bool _initialized = false;
  bool _paused = false;

  // Callbacks (optional — untuk UI).
  void Function(bool connected)? onConnectionChanged;
  void Function(bool success)? onPublishResult;
  void Function(Map<String, dynamic> ack)? onAck;
  void Function()? onReconnected; // selepas connect/reconnect + flush queue
  void Function()? onReconnectExhausted; // 5x auto gagal
  void Function(int attempt, int max)? onReconnectAttempt; // info cubaan

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  bool get isInitialized => _initialized;
  bool get isExhausted => _exhausted;
  int get queueLength => MqttOfflineQueue().length;

  void pause() => _paused = true;
  void resume() => _paused = false;

  Future<void> init({required String deviceId}) async {
    if (_initialized && _deviceId == deviceId && isConnected) {
      onConnectionChanged?.call(true);
      return;
    }
    if (_initialized && _deviceId != deviceId) {
      disconnect(); // device tukar — reset bersih
    }
    _deviceId = deviceId;
    _initialized = true;
    _intentional = false;
    _exhausted = false;
    _reconnectAttempts = 0;
    _backoffSec = 2;
    await _createAndConnect();
  }

  /// Reconnect manual — reset counter, cuba 5x lagi dari awal.
  Future<void> manualReconnect() async {
    if (_deviceId == null) return;
    _reconnectTimer?.cancel();
    _intentional = false;
    _exhausted = false;
    _reconnectAttempts = 0;
    _backoffSec = 2;
    if (kDebugMode) debugPrint('🔁 [MQTT] Manual reconnect started');
    await _createAndConnect();
  }

  /// Dipanggil bila app kembali foreground. Kalau dah exhausted & belum
  /// connect, cuba semula (reset counter).
  Future<void> resumeReconnect() async {
    if (_deviceId == null) return;
    if (isConnected) return;
    if (_exhausted) {
      if (kDebugMode) debugPrint('▶️ [MQTT] Resume — retrying reconnect');
      await manualReconnect();
    }
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
    client.logging(on: kDebugMode);
    client.keepAlivePeriod = 20;
    client.autoReconnect = false; // kita urus reconnect sendiri
    client.connectTimeoutPeriod = 15000;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    // LWT — broker hantar ni kalau APK putus mendadak.
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
      // Kejayaan diuruskan dalam _onConnected.
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [MQTT] Connect failed: $e');
      onConnectionChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    _intentional = false;
    _exhausted = false;
    _reconnectAttempts = 0; // reset selepas berjaya
    _backoffSec = 2;
    if (kDebugMode) debugPrint('✅ [MQTT] Connected');
    onConnectionChanged?.call(true);

    // Status online (retain).
    _rawPublish(
      MqttTopics(_deviceId!).status,
      jsonEncode({'online': true, 'ts': _nowMs()}),
      retain: true,
      notify: false,
    );

    // Subscribe ACK dari backend.
    _client!.subscribe(MqttTopics(_deviceId!).ack, MqttQos.atLeastOnce);

    // Listen mesej masuk (ACK).
    _updatesSub?.cancel();
    _updatesSub = _client!.updates!.listen(_onMessages);

    // Flush offline queue → backfill.
    if (!MqttOfflineQueue().isEmpty) {
      MqttOfflineQueue().flush(_client!, _deviceId!);
    }

    // Push snapshot terkini (GPS / sensor cache) — bukan bergantung polling Transmission.
    onReconnected?.call();
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

    // Sudah habis cubaan → stop, minta manual.
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _exhausted = true;
      if (kDebugMode) {
        debugPrint('🛑 [MQTT] Reconnect attempts exhausted ($_maxReconnectAttempts)');
      }
      onReconnectExhausted?.call();
      return;
    }

    _reconnectAttempts++;
    final delay = _backoffSec;
    onReconnectAttempt?.call(_reconnectAttempts, _maxReconnectAttempts);
    if (kDebugMode) {
      debugPrint(
        '🔄 [MQTT] Reconnect #$_reconnectAttempts/$_maxReconnectAttempts in ${delay}s',
      );
    }
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      _backoffSec = (_backoffSec * 2).clamp(2, 32); // 2,4,8,16,32
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
  /// [data] boleh override status_live (cth offline pada exit snapshot).
  Map<String, dynamic> _buildPayload(Map<String, dynamic> data) {
    return <String, dynamic>{
      'node_id': _deviceId,
      'send_dt': _nowIso(),
      if (!data.containsKey('status_live')) 'status_live': 'online',
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
    _exhausted = false;
    _reconnectAttempts = 0;
    onConnectionChanged?.call(false);
    if (kDebugMode) debugPrint('🔌 [MQTT] Disconnected (intentional)');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}