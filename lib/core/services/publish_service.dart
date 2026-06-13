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
import 'gps_smoother.dart';
import 'sensor_state_service.dart';

/// Rekod GPS + snapshot sensor pada masa event (untuk bundle/backfill).
class _GpsTickRecord {
  const _GpsTickRecord({
    required this.fix,
    required this.sensorData,
    required this.transmissionType,
  });

  final LocationFix fix;
  final List<dynamic> sensorData;
  final String transmissionType;
}

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
  final SensorStateService _sensorState = SensorStateService();
  final GpsSmoother _smoother = GpsSmoother(3); // Gunakan 3 titik untuk purata

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

  /// Salinan payload sensor terakhir (delegasi SensorStateService).
  List<dynamic>? get lastModbusSensorPayload =>
      _sensorState.hasData ? _sensorState.payload : null;

  /// Fix lokasi terakhir yang berjaya dipakai untuk publish Modbus (fallback bila GPS stuck).
  LocationFix? _lastReliableModbusFix;

  DateTime _lastExitPublish = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Scheduler / GPS state ---
  Timer? _schedulerTimer;
  StreamSubscription<LocationFix>? _locSub;
  bool _ticking = false;

  /// Buffer GPS event + sensor snapshot semasa event (≥1/s untuk backfill).
  final List<_GpsTickRecord> _gpsEventBuffer = [];

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
  // void onLocationEvent(LocationFix fix) {
  //   _pendingFix = fix;
  //   _updateMotionState(fix, DateTime.now());
  // }
  void onLocationEvent(LocationFix fix) {
    _smoother.add(fix);
    final smoothed = _smoother.getSmoothedFix() ?? fix;
    _pendingFix = smoothed;
    _updateMotionState(smoothed, DateTime.now());

    final snap = _sensorState.snapshot();
    _gpsEventBuffer.add(
      _GpsTickRecord(
        fix: smoothed,
        sensorData: snap.sensorData,
        transmissionType: snap.transmissionType,
      ),
    );
  }

  /// Publish setiap tik: latest → /bundle, selebihnya → /backfill.
  void _tickPublishTask() {
    List<_GpsTickRecord> records;
    if (_gpsEventBuffer.isNotEmpty) {
      records = List<_GpsTickRecord>.from(_gpsEventBuffer);
      _gpsEventBuffer.clear();
    } else if (_pendingFix != null) {
      final snap = _sensorState.snapshot();
      records = [
        _GpsTickRecord(
          fix: _pendingFix!,
          sensorData: snap.sensorData,
          transmissionType: snap.transmissionType,
        ),
      ];
    } else {
      return;
    }

    unawaited(_ensureMeta());

    final latest = records.last;
    if (records.length > 1) {
      final backfillMaps = records
          .sublist(0, records.length - 1)
          .map(_payloadMapFromRecord)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (backfillMaps.isNotEmpty) {
        _mqtt.publishBackfillBatch(backfillMaps);
        if (kDebugMode) {
          debugPrint(
            '📤 [Publish] backfill ${backfillMaps.length} GPS events '
            '(sensor attached)',
          );
        }
      }
    }

    _publishFromRecord(latest);
    _lastPublishedFix = latest.fix;
    _lastPublishAt = DateTime.now();
    _lastIdleHeartbeatAt = _lastPublishAt;
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

    if (_modbusTransmissionActive && _sensorState.hasData) {
      return publishModbus(
        sensorData: _sensorState.payload,
        transmissionType: _sensorState.transmissionType,
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

    final snap = _sensorState.snapshot();
    _publish(
      latitude: f.latitude,
      longitude: f.longitude,
      speed: f.speed,
      heading: f.heading,
      sensorData: snap.sensorData,
      transmissionType: snap.transmissionType,
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

    final snap = _sensorState.snapshot();
    _publish(
      latitude: f.latitude,
      longitude: f.longitude,
      speed: f.speed,
      heading: f.heading,
      sensorData: snap.sensorData,
      transmissionType: snap.transmissionType,
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
    _sensorState.update(
      sensorData: sensorData,
      transmissionType: transmissionType,
    );

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
      txType = transmissionType ?? _sensorState.transmissionType;
    } else {
      final snap = _sensorState.snapshot();
      sensors = snap.sensorData;
      txType = transmissionType ?? snap.transmissionType;
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
  // CORE — bina payload + publish bundle / backfill
  // ---------------------------------------------------------------

  void _publishFromRecord(
    _GpsTickRecord record, {
    String statusLive = PublishStatusLive.online,
  }) {
    _publish(
      latitude: record.fix.latitude,
      longitude: record.fix.longitude,
      speed: record.fix.speed,
      heading: record.fix.heading,
      sensorData: record.sensorData,
      transmissionType: record.transmissionType,
      statusLive: statusLive,
    );
  }

  Map<String, dynamic>? _payloadMapFromRecord(
    _GpsTickRecord record, {
    String statusLive = PublishStatusLive.online,
  }) {
    return _buildPayloadMap(
      latitude: record.fix.latitude,
      longitude: record.fix.longitude,
      speed: record.fix.speed,
      heading: record.fix.heading,
      sensorData: record.sensorData,
      transmissionType: record.transmissionType,
      statusLive: statusLive,
    );
  }

  Map<String, dynamic>? _buildPayloadMap({
    required double? latitude,
    required double? longitude,
    required double speed,
    required double? heading,
    required List<dynamic> sensorData,
    String transmissionType = 'Unknown',
    String statusLive = PublishStatusLive.online,
  }) {
    if (latitude == null || longitude == null) return null;

    final movingThreshold =
        TrackingPublishConfig.motionMovingSpeedThresholdMps;
    final sendDt = DateTime.now().toString().substring(0, 19);

    return <String, dynamic>{
      'data_type': 'MG',
      'node_id': _nodeId ?? 'unknown',
      'send_dt': sendDt,
      'status_live': statusLive,
      'motion_status': speed > movingThreshold ? 'moving' : 'idle',
      'speed': speed,
      'speed_unit': MetricUnits.metersPerSecond,
      if (heading != null) 'heading': heading,
      if (heading != null) 'heading_unit': MetricUnits.degrees,
      'latitude': latitude,
      'longitude': longitude,
      ...DeviceMetricsService().buildPayloadFields(),
      'transmission_type': transmissionType,
      'sensor_data': sensorData,
      'name': _deviceName ?? _nodeId ?? 'unknown',
      if (_sessionToken != null) 'session_token': _sessionToken,
    };
  }

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

    final payload = _buildPayloadMap(
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      heading: heading,
      sensorData: sensorData,
      transmissionType: transmissionType,
      statusLive: statusLive,
    );
    if (payload == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] skip — missing latitude/longitude');
      }
      return;
    }

    _mqtt.publishBundle(payload);

    if (kDebugMode) {
      debugPrint('📤 [Publish] bundle sent — status_live=$statusLive '
          'sensor=$sensorData lat=${payload['latitude']} '
          'lon=${payload['longitude']} tx=$transmissionType '
          'connected=${_mqtt.isConnected}');
    }
  }

  bool get isMqttConnected => _mqtt.isConnected;
}
