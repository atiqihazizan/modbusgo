// PublishService — PINTU TUNGGAL untuk semua publish tracking bundle.
//
// Reka bentuk (disahkan dengan keputusan projek — lihat history-development/publish-gps-modbus-flow.md):
//   - GPS-change publish di-hold hanya semasa polling loop (pauseGps / resumeGps).
//   - Skrin Transmission aktif → setTransmissionScreenActive (cache sensor untuk exit snapshot).
//   - Data Modbus (polling) → publishModbus(): lat/lon terkini; stuck → last reliable fix.
//   - GPS berubah → publishGps(): sensor_data [-1]; skip jika pause polling.
//   - Keluar app / background / pop Transmission → publishExitSnapshot(): semua medan
//     penting (lat/lon, speed, heading, bateri, suhu, …); status_live 'offline';
//     sensor_data ikut konteks (Modbus aktif → nilai sensor semasa, else [-1]).
//   - Idle watchdog: selepas publish berjaya → timer 10s; jika tiada publish baru
//     dan MQTT connected → heartbeat status_live idle setiap 3s (henti bila pauseGps
//     atau publish online/offline).
//
// Service ini TIDAK menggantikan MqttService/LocationService — ia membungkus
// keduanya supaya logik bina-payload + kawalan pause berada di SATU tempat.
//
// Payload kekal padan backend v3 (lihat MqttService.publishBundle):
//   {data_type:'MG', latitude, longitude, speed, speed_unit, heading?, heading_unit?,
//    cpu_temp?, cpu_temp_unit, battery_level?, battery_level_unit, thermal_status?, ...}
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
      // Session token: jana sekali kalau belum ada (kekal sepanjang pemasangan).
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

  // Bila true, GPS-change publish ditahan (Modbus sedang pegang kawalan).
  bool _gpsPaused = false;
  bool get isGpsPaused => _gpsPaused;

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

  // Throttle GPS publish — elak spam bila fix masuk laju. Modbus TIDAK di-throttle
  // di sini sebab kadarnya dikawal oleh polling loop transport.
  DateTime _lastGpsPublish = DateTime.fromMillisecondsSinceEpoch(0);

  double? _lastPublishedLat;
  double? _lastPublishedLon;

  Timer? _idleWatchTimer;
  Timer? _idleHeartbeatTimer;

  /// Publish berjaya pertama dalam sesi guna [TrackingPublishConfig.idleWatchAfterLaunch].
  bool _firstIdleWatchPending = true;

  bool _coordinatesChanged(double lat, double lon) {
    final eps = TrackingPublishConfig.coordinateChangeEpsilonDegrees;
    if (_lastPublishedLat == null || _lastPublishedLon == null) return true;
    return (lat - _lastPublishedLat!).abs() > eps ||
        (lon - _lastPublishedLon!).abs() > eps;
  }

  // ---------------------------------------------------------------
  // KAWALAN SKRIN / PAUSE POLLING (skrin Transmission)
  // ---------------------------------------------------------------

  /// Masuk/keluar skrin Transmission (bukan pause GPS — itu ikut polling sahaja).
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

  /// Start polling loop — tahan GPS-change publish supaya tidak bertindih Modbus.
  void pauseGps() {
    _gpsPaused = true;
    _stopIdleScheduling();
    if (kDebugMode) {
      debugPrint('⏸️ [Publish] GPS-change held (polling active)');
    }
  }

  /// Stop polling loop — benarkan GPS-change semula (masih boleh di skrin Transmit).
  void resumeGps() {
    _gpsPaused = false;
    if (kDebugMode) debugPrint('▶️ [Publish] GPS-change resumed (polling stopped)');
  }

  // ---------------------------------------------------------------
  // IDLE WATCHDOG (10s selepas publish → heartbeat idle 3s)
  // ---------------------------------------------------------------

  void _stopIdleHeartbeat() {
    _idleHeartbeatTimer?.cancel();
    _idleHeartbeatTimer = null;
  }

  void _stopIdleScheduling() {
    _idleWatchTimer?.cancel();
    _idleWatchTimer = null;
    _stopIdleHeartbeat();
  }

  /// Sebelum hantar bundle: batalkan watchdog; henti interval kecuali publish idle.
  void _onBeforePublish(String statusLive) {
    _idleWatchTimer?.cancel();
    _idleWatchTimer = null;
    if (statusLive != PublishStatusLive.idle) {
      _stopIdleHeartbeat();
    }
  }

  /// Selepas bundle dihantar/queued: mulakan semula watchdog atau matikan semua.
  void _onAfterSuccessfulPublish(String statusLive) {
    if (statusLive == PublishStatusLive.offline || _gpsPaused) {
      _stopIdleScheduling();
      return;
    }
    final watch = _firstIdleWatchPending
        ? TrackingPublishConfig.idleWatchAfterLaunch
        : TrackingPublishConfig.idleWatchAfterPublish;
    _firstIdleWatchPending = false;

    _idleWatchTimer?.cancel();
    _idleWatchTimer = Timer(watch, _onIdleWatchElapsed);
    if (kDebugMode) {
      debugPrint(
        '⏱️ [Publish] idle watch ${watch.inSeconds}s '
        '(after status_live=$statusLive)',
      );
    }
  }

  void _onIdleWatchElapsed() {
    _idleWatchTimer = null;
    if (_gpsPaused || !_mqtt.isConnected) {
      if (kDebugMode) {
        debugPrint(
          '⏭️ [Publish] idle watch skip — '
          'paused=$_gpsPaused connected=${_mqtt.isConnected}',
        );
      }
      return;
    }
    _startIdleHeartbeat();
  }

  void _startIdleHeartbeat() {
    if (_idleHeartbeatTimer != null) return;
    if (_lastPublishedLat == null || _lastPublishedLon == null) return;

    if (kDebugMode) {
      debugPrint(
        '💤 [Publish] idle heartbeat every '
        '${TrackingPublishConfig.idleHeartbeatInterval.inSeconds}s',
      );
    }

    unawaited(_ensureMeta());
    _publishIdleHeartbeat();
    _idleHeartbeatTimer = Timer.periodic(
      TrackingPublishConfig.idleHeartbeatInterval,
      (_) => _publishIdleHeartbeat(),
    );
  }

  void _publishIdleHeartbeat() {
    if (_gpsPaused || !_mqtt.isConnected) {
      _stopIdleScheduling();
      return;
    }
    final lat0 = _lastPublishedLat;
    final lon0 = _lastPublishedLon;
    if (lat0 == null || lon0 == null) return;

    final fix = _location.lastFix;
    final lat = fix?.latitude ?? lat0;
    final lon = fix?.longitude ?? lon0;

    if (_coordinatesChanged(lat, lon)) {
      _stopIdleHeartbeat();
      if (fix != null) {
        _publish(
          latitude: fix.latitude,
          longitude: fix.longitude,
          speed: fix.speed,
          heading: fix.heading,
          sensorData: const [-1],
          statusLive: PublishStatusLive.online,
        );
      }
      return;
    }

    _publish(
      latitude: lat,
      longitude: lon,
      speed: fix?.speed ?? 0,
      heading: fix?.heading,
      sensorData: const [-1],
      statusLive: PublishStatusLive.idle,
    );
  }

  // ---------------------------------------------------------------
  // PUBLISH DARI GPS (luar skrin Transmission)
  // ---------------------------------------------------------------

  /// Publish bila lokasi berubah. Skip kalau GPS dipause (Modbus pegang kawalan)
  /// atau belum cukup jarak masa (throttle). sensor_data = [-1] (tiada sensor).
  /// Return true kalau publish dihantar; false kalau di-skip.
  bool publishGps(LocationFix fix) {
    if (_gpsPaused) return false;
    if (!_coordinatesChanged(fix.latitude, fix.longitude)) return false;

    final now = DateTime.now();
    if (now.difference(_lastGpsPublish) <
        TrackingPublishConfig.gpsChangeMinGap) {
      return false;
    }
    _lastGpsPublish = now;

    _publish(
      latitude: fix.latitude,
      longitude: fix.longitude,
      speed: fix.speed,
      heading: fix.heading,
      sensorData: const [-1],
    );
    return true;
  }

  /// Publish manual (butang emit). Delegasi ke [publishCurrentSnapshot].
  Future<bool> publishManual({LocationFix? fix}) =>
      publishCurrentSnapshot(fix: fix);

  /// Snapshot lokasi semasa (emit manual, refresh GPS, publish awal Home).
  /// Abaikan throttle koordinat; hormati [pauseGps]. Offline → queue kecuali
  /// [requireConnected].
  Future<bool> publishCurrentSnapshot({
    LocationFix? fix,
    Duration locTimeout = TrackingPublishConfig.locationTimeoutSnapshot,
    bool requireConnected = false,
  }) async {
    if (_gpsPaused) return false;
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
    return true;
  }

  // ---------------------------------------------------------------
  // PUBLISH DARI MODBUS (dalam skrin Transmission)
  // ---------------------------------------------------------------

  /// Data Modbus diterima → baca lat/lon SEGAR → publish dengan sensor sebenar.
  ///
  /// [sensorData] = nilai register yang dah di-parse (cth [25.5, 30.2]).
  ///   Untuk error/timeout, hantar penanda (cth ['ERR'] / ['TMO']) ikut kontrak
  ///   yang dipersetujui di layer transport — service ini hantar apa adanya.
  ///
  /// Strategi lokasi: lastFix stream → one-shot segar → last reliable (stuck/tiada baru).
  /// Return true kalau publish dihantar; false hanya bila tiada sebarang fix pernah.
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
  // PUBLISH KELUAR / BACKGROUND (graceful exit — bukan force-kill)
  // ---------------------------------------------------------------

  /// Snapshot penuh untuk DB: lokasi, kelajuan, heading, bateri, suhu, dll.
  /// [sensorData] null → [-1], kecuali Modbus aktif guna cache sensor terakhir.
  /// Abaikan [pauseGps]; offline → queue MQTT.
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
    _onBeforePublish(statusLive);
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
    _lastPublishedLat = lat;
    _lastPublishedLon = lon;

    if (kDebugMode) {
      debugPrint('📤 [Publish] bundle sent — status_live=$statusLive '
          'sensor=$sensorData lat=${lat.toStringAsFixed(4)} '
          'lon=${lon.toStringAsFixed(4)} tx=$transmissionType '
          'connected=${_mqtt.isConnected}');
    }

    _onAfterSuccessfulPublish(statusLive);
  }

  /// Status sambungan (untuk UI indikator). Delegasi ke MqttService.
  bool get isMqttConnected => _mqtt.isConnected;
}