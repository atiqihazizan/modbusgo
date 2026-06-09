// PublishService — PINTU TUNGGAL untuk semua publish tracking bundle.
//
// Reka bentuk:
//   - GPS stream event → kemas kini _pendingFix sahaja (tiada get, tiada publish).
//   - Scheduler ticker (500ms) → publish sentiasa setiap tik (fasa R&D).
//   - Poll Modbus dalam tik yang sama.
//   - Publish GPS ditapis ikut jarak meter + throttle + maxPublishInterval.
//   - Skrin Transmission aktif → setTransmissionScreenActive (cache sensor untuk exit).
//   - Data Modbus (polling) → publishModbus(): lat/lon terkini + sensor_data.
//   - Keluar app / background / pop Transmission → publishExitSnapshot(): offline.
//
// Payload kekal padan backend v3 (lihat MqttService.publishBundle).
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../constants/metric_units.dart';
import '../constants/tracking_publish_config.dart';
import 'device_identity_service.dart';
import 'device_metrics_service.dart';
import 'local_storage_service.dart';
import 'location_service.dart';
import 'mqtt_service.dart';

/// Nilai [status_live] dalam bundle tracking (selari backend).
abstract final class PublishStatusLive {
  static const String online = TrackingPublishConfig.statusLiveOnline;
  static const String idle = TrackingPublishConfig.statusLiveIdle;
  static const String offline = TrackingPublishConfig.statusLiveOffline;
}

enum _MotionState { unknown, moving, idle }

class PublishService {
  PublishService._internal();
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;

  final MqttService _mqtt = MqttService();
  final LocationService _location = LocationService();

  String? _nodeId;
  String? _deviceName;
  String? _sessionToken;

  Future<void> _ensureMeta() async {
    if (_nodeId != null) return;
    try {
      _nodeId = await DeviceIdentityService().getDeviceId();
      final storage = LocalStorageService();
      final info = await storage.getDeviceInfo();
      _deviceName = (info?['name']?.isNotEmpty == true) ? info!['name'] : null;
      var token = await storage.getSessionToken();
      if (token == null || token.isEmpty) {
        token = 'sess-${DateTime.now().millisecondsSinceEpoch}';
        await storage.saveSessionToken(token);
      }
      _sessionToken = token;
    } catch (_) {
      _nodeId ??= 'unknown';
    }
  }

  /// Skrin Transmission aktif — untuk sertakan sensor cache bila app ke background.
  bool _modbusTransmissionActive = false;
  bool get isModbusTransmissionActive => _modbusTransmissionActive;

  /// Salinan payload sensor Modbus terakhir (untuk publish keluar skrin).
  List<dynamic>? get lastModbusSensorPayload =>
      _lastModbusSensorPayload == null
          ? null
          : List<dynamic>.from(_lastModbusSensorPayload!);

  List<dynamic>? _lastModbusSensorPayload;
  String _lastModbusTransmissionType = 'Unknown';

  /// Fix lokasi terakhir yang berjaya dipakai untuk publish Modbus (fallback bila GPS stuck).
  LocationFix? _lastReliableModbusFix;

  DateTime _lastExitPublish = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Scheduler / GPS state ---
  Timer? _schedulerTimer;
  StreamSubscription<LocationFix>? _locSub;
  bool _ticking = false;

  LocationFix? _pendingFix;
  LocationFix? _lastPublishedFix;
  bool _dirty = false;
  _MotionState _motion = _MotionState.unknown;

  DateTime _lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastIdleHeartbeatAt = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Modbus poller hook (dilampir dari skrin Transmission) ---
  bool Function()? _modbusCanPoll;
  void Function()? _modbusPollOnce;
  Duration _modbusPollInterval = const Duration(milliseconds: 1000);
  DateTime _lastModbusPollAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------------------------------------------------------
  // SCHEDULER
  // ---------------------------------------------------------------

  /// Mulakan ticker + langganan GPS event (idempotent).
  void startScheduler() {
    _locSub ??= _location.stream.listen(onLocationEvent);
    if (_schedulerTimer != null) return;
    _schedulerTimer = Timer.periodic(
      TrackingPublishConfig.schedulerTickInterval,
      (_) => unawaited(_onTick()),
    );
    if (kDebugMode) {
      debugPrint(
        '⏱️ [Publish] scheduler started '
        '(${TrackingPublishConfig.schedulerTickInterval.inMilliseconds}ms)',
      );
    }
  }

  /// Hentikan ticker dan langganan GPS.
  void stopScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    _locSub?.cancel();
    _locSub = null;
    if (kDebugMode) debugPrint('⏹️ [Publish] scheduler stopped');
  }

  Future<void> _onTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      _tickPublishTask();
      _modbusTask();
    } finally {
      _ticking = false;
    }
  }

  double _distanceFromLastPublished(LocationFix fix) {
    final ref = _lastPublishedFix;
    if (ref == null) return double.infinity;
    return LocationService.distanceMeters(ref, fix);
  }

  void _updateMotionState(LocationFix fix, DateTime now) {
    final dist = _distanceFromLastPublished(fix);
    final minMove = TrackingPublishConfig.minMoveDistanceMeters;
    final redundant = TrackingPublishConfig.redundantDistanceMeters;

    if (dist >= minMove) {
      _motion = _MotionState.moving;
      _lastMoveAt = now;
      _dirty = true;
    } else if (dist < redundant) {
      if (now.difference(_lastMoveAt) >=
          TrackingPublishConfig.idleConfirmDuration) {
        _motion = _MotionState.idle;
      }
    }
  }

  /// GPS event: simpan fix terkini — publish diurus timer 500ms.
  void onLocationEvent(LocationFix fix) {
    _pendingFix = fix;
    _updateMotionState(fix, DateTime.now());
  }

  /// Publish setiap tik scheduler (R&D: ~2x/s) guna [_pendingFix] dari event.
  void _tickPublishTask() {
    final fix = _pendingFix;
    if (fix == null) return;
    _publishOnline(fix, DateTime.now());
  }

  // --- Logik publish berjadual (throttle/jarak/redundant) — disimpan untuk fasa prod.
  // void _tryPublishOnline() { ... }
  // void _flushTask() { ... }

  void _publishOnline(LocationFix fix, DateTime now) {
    if (kDebugMode && _lastPublishAt.millisecondsSinceEpoch > 0) {
      debugPrint(
        '⏱️ [Publish] tick gap ${now.difference(_lastPublishAt).inMilliseconds}ms',
      );
    }
    unawaited(_ensureMeta());
    _publish(
      latitude: fix.latitude,
      longitude: fix.longitude,
      speed: fix.speed,
      heading: fix.heading,
      sensorData: const [-1],
      transmissionType: 'GPS',
      statusLive: PublishStatusLive.online,
    );
    _lastPublishedFix = fix;
    _lastPublishAt = now;
    _lastIdleHeartbeatAt = now;
  }

  void _modbusTask() {
    final poll = _modbusPollOnce;
    final canPoll = _modbusCanPoll;
    if (poll == null || canPoll == null) return;
    if (!canPoll()) return;

    final now = DateTime.now();
    if (now.difference(_lastModbusPollAt) < _modbusPollInterval) return;

    _lastModbusPollAt = now;
    poll();
  }

  // ---------------------------------------------------------------
  // KAWALAN SKRIN / MODBUS POLLER
  // ---------------------------------------------------------------

  void setTransmissionScreenActive(bool active) {
    _modbusTransmissionActive = active;
    if (kDebugMode) {
      debugPrint(
        active
            ? '📡 [Publish] Transmission screen active'
            : '📡 [Publish] Transmission screen inactive',
      );
    }
  }

  /// Lampirkan hook poll Modbus dari skrin Transmission.
  void attachModbusPoller({
    required bool Function() canPoll,
    required void Function() pollOnce,
    required Duration pollInterval,
  }) {
    _modbusCanPoll = canPoll;
    _modbusPollOnce = pollOnce;
    _modbusPollInterval = pollInterval;
    _lastModbusPollAt = DateTime.fromMillisecondsSinceEpoch(0);
    startScheduler();
    if (kDebugMode) {
      debugPrint(
        '🔗 [Publish] Modbus poller attached '
        '(interval=${pollInterval.inMilliseconds}ms)',
      );
    }
  }

  /// Tanggal hook poll Modbus.
  void detachModbusPoller() {
    _modbusCanPoll = null;
    _modbusPollOnce = null;
    if (kDebugMode) debugPrint('🔓 [Publish] Modbus poller detached');
  }

  // ---------------------------------------------------------------
  // PUBLISH SNAPSHOT / MANUAL
  // ---------------------------------------------------------------

  /// Publish manual (butang emit). Delegasi ke [publishCurrentSnapshot].
  Future<bool> publishManual({LocationFix? fix}) =>
      publishCurrentSnapshot(fix: fix);

  /// Push snapshot penuh bila MQTT sambung semula (connect / reconnect).
  Future<bool> publishReconnectSnapshot() async {
    if (!_mqtt.isConnected) return false;

    await _ensureMeta();
    await DeviceMetricsService().refreshBattery();

    if (_modbusTransmissionActive &&
        _lastModbusSensorPayload != null &&
        _lastModbusSensorPayload!.isNotEmpty) {
      return publishModbus(
        sensorData: List<dynamic>.from(_lastModbusSensorPayload!),
        transmissionType: _lastModbusTransmissionType,
      );
    }

    var f = _location.lastFix;
    if (f == null ||
        (f.accuracy != null &&
            f.accuracy! >
                TrackingPublishConfig.maxAcceptableAccuracyMeters)) {
      f = await _location.getCurrentFix(
        timeout: TrackingPublishConfig.locationTimeoutSnapshot,
      );
    }

    if (f == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] reconnect snapshot skip — no GPS fix');
      }
      return false;
    }

    _publish(
      latitude: f.latitude,
      longitude: f.longitude,
      speed: f.speed,
      heading: f.heading,
      sensorData: const [-1],
      transmissionType: 'GPS',
    );
    _lastPublishedFix = f;
    _lastPublishAt = DateTime.now();
    _dirty = false;

    if (kDebugMode) {
      debugPrint('📤 [Publish] reconnect snapshot sent');
    }
    return true;
  }

  /// Snapshot lokasi semasa (emit manual, refresh GPS, publish awal Home).
  Future<bool> publishCurrentSnapshot({
    LocationFix? fix,
    Duration locTimeout = TrackingPublishConfig.locationTimeoutSnapshot,
    bool requireConnected = false,
  }) async {
    if (requireConnected && !_mqtt.isConnected) return false;

    await _ensureMeta();

    var f = fix ?? _location.lastFix;
    if (f == null ||
        (f.accuracy != null &&
            f.accuracy! >
                TrackingPublishConfig.maxAcceptableAccuracyMeters)) {
      f = await _location.getCurrentFix(timeout: locTimeout);
    }

    if (f == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] snapshot skip — no GPS fix');
      }
      return false;
    }

    _publish(
      latitude: f.latitude,
      longitude: f.longitude,
      speed: f.speed,
      heading: f.heading,
      sensorData: const [-1],
    );
    _lastPublishedFix = f;
    _lastPublishAt = DateTime.now();
    _dirty = false;
    return true;
  }

  // ---------------------------------------------------------------
  // PUBLISH DARI MODBUS (dalam skrin Transmission)
  // ---------------------------------------------------------------

  Future<bool> publishModbus({
    required List<dynamic> sensorData,
    String transmissionType = 'Unknown',
    Duration locTimeout = TrackingPublishConfig.locationTimeoutModbus,
  }) async {
    await _ensureMeta();
    final fix = await _resolveFixForModbusPublish(locTimeout: locTimeout);
    if (fix == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] Modbus skip — no GPS fix available');
      }
      return false;
    }

    _lastReliableModbusFix = fix;
    _lastModbusSensorPayload = List<dynamic>.from(sensorData);
    _lastModbusTransmissionType = transmissionType;

    _publish(
      latitude: fix.latitude,
      longitude: fix.longitude,
      speed: fix.speed,
      heading: fix.heading,
      sensorData: sensorData,
      transmissionType: transmissionType,
    );
    _lastPublishedFix = fix;
    _lastPublishAt = DateTime.now();
    _dirty = false;
    return true;
  }

  Future<LocationFix?> _resolveFixForModbusPublish({
    required Duration locTimeout,
  }) async {
    var fix = _location.lastFix;
    if (fix == null) {
      try {
        fix = await _location
            .getCurrentFix(timeout: locTimeout)
            .timeout(locTimeout, onTimeout: () => null);
      } catch (_) {
        fix = null;
      }
    }
    return fix ?? _lastReliableModbusFix;
  }

  // ---------------------------------------------------------------
  // PUBLISH KELUAR / BACKGROUND
  // ---------------------------------------------------------------

  Future<bool> publishExitSnapshot({
    List<dynamic>? sensorData,
    String? transmissionType,
    String exitContext = 'exit',
    Duration locTimeout = TrackingPublishConfig.locationTimeoutExit,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastExitPublish) <
        TrackingPublishConfig.exitPublishDebounce) {
      if (kDebugMode) {
        debugPrint('⏭️ [Publish] exit skip debounce ($exitContext)');
      }
      return false;
    }

    await _ensureMeta();
    await DeviceMetricsService().refreshBattery();

    LocationFix? fix = _location.lastFix;
    if (fix == null) {
      try {
        fix = await _location
            .getCurrentFix(timeout: locTimeout)
            .timeout(locTimeout, onTimeout: () => null);
      } catch (_) {
        fix = null;
      }
    }

    if (fix == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] exit skip — no GPS ($exitContext)');
      }
      return false;
    }

    List<dynamic> sensors;
    String txType;
    if (sensorData != null) {
      sensors = sensorData;
      txType = transmissionType ?? _lastModbusTransmissionType;
    } else if (_modbusTransmissionActive &&
        _lastModbusSensorPayload != null &&
        _lastModbusSensorPayload!.isNotEmpty) {
      sensors = List<dynamic>.from(_lastModbusSensorPayload!);
      txType = transmissionType ?? _lastModbusTransmissionType;
    } else {
      sensors = const [-1];
      txType = transmissionType ?? 'GPS';
    }

    _lastExitPublish = now;
    detachModbusPoller();
    stopScheduler();

    _publish(
      latitude: fix.latitude,
      longitude: fix.longitude,
      speed: fix.speed,
      heading: fix.heading,
      sensorData: sensors,
      transmissionType: txType,
      statusLive: PublishStatusLive.offline,
    );

    if (kDebugMode) {
      debugPrint(
        '📤 [Publish] exit snapshot ($exitContext) '
        'status_live=${PublishStatusLive.offline} sensor=$sensors',
      );
    }
    return true;
  }

  // ---------------------------------------------------------------
  // CORE — satu-satunya tempat bina payload + panggil mqtt
  // ---------------------------------------------------------------

  void _publish({
    required double? latitude,
    required double? longitude,
    required double speed,
    required double? heading,
    required List<dynamic> sensorData,
    String transmissionType = 'Unknown',
    String statusLive = PublishStatusLive.online,
  }) {
    unawaited(DeviceMetricsService().refreshBattery());

    if (latitude == null || longitude == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] skip — missing latitude/longitude');
      }
      return;
    }
    final lat = latitude;
    final lon = longitude;
    final movingThreshold =
        TrackingPublishConfig.motionMovingSpeedThresholdMps;
    final sendDt = DateTime.now().toString().substring(0, 19);

    final payload = <String, dynamic>{
      'data_type': 'MG',
      'node_id': _nodeId ?? 'unknown',
      'send_dt': sendDt,
      'status_live': statusLive,
      'motion_status': speed > movingThreshold ? 'moving' : 'idle',
      'speed': speed,
      'speed_unit': MetricUnits.metersPerSecond,
      if (heading != null) 'heading': heading,
      if (heading != null) 'heading_unit': MetricUnits.degrees,
      'latitude': lat,
      'longitude': lon,
      ...DeviceMetricsService().buildPayloadFields(),
      'transmission_type': transmissionType,
      'sensor_data': sensorData,
      'name': _deviceName ?? _nodeId ?? 'unknown',
      if (_sessionToken != null) 'session_token': _sessionToken,
    };

    _mqtt.publishBundle(payload);

    if (kDebugMode) {
      debugPrint('📤 [Publish] bundle sent — status_live=$statusLive '
          'sensor=$sensorData lat=${lat.toStringAsFixed(4)} '
          'lon=${lon.toStringAsFixed(4)} tx=$transmissionType '
          'connected=${_mqtt.isConnected}');
    }
  }

  bool get isMqttConnected => _mqtt.isConnected;
}
