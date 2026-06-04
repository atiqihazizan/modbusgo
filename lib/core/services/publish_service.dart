// PublishService — PINTU TUNGGAL untuk semua publish tracking bundle.
//
// Reka bentuk (disahkan dengan keputusan projek):
//   - Mutually exclusive: Modbus (dalam skrin Transmission) ATAU GPS (luar skrin).
//   - Masuk skrin Transmission → pauseGps(): GPS-change publish ditahan.
//   - Keluar skrin Transmission → resumeGps(): GPS-change publish sambung semula.
//   - Data Modbus masuk → publishModbus(): baca lat/lon segar, publish sensor sebenar.
//   - GPS berubah (luar skrin) → publishGps(): sensor_data [-1] (tiada data sensor).
//   - Keluar app / background / pop Transmission → publishExitSnapshot(): semua medan
//     penting (lat/lon, speed, heading, bateri, suhu, …); sensor_data ikut konteks
//     (Modbus aktif → nilai sensor semasa, else [-1]).
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
import 'device_identity_service.dart';
import 'device_metrics_service.dart';
import 'local_storage_service.dart';
import 'location_service.dart';
import 'mqtt_service.dart';

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

  DateTime _lastExitPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _exitPublishDebounce = Duration(seconds: 4);

  // Throttle GPS publish — elak spam bila fix masuk laju. Modbus TIDAK di-throttle
  // di sini sebab kadarnya dikawal oleh polling loop transport.
  DateTime _lastGpsPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _gpsMinGap = Duration(seconds: 3);

  double? _lastPublishedLat;
  double? _lastPublishedLon;
  static const double _coordEpsilon = 5e-5;

  bool _coordinatesChanged(double lat, double lon) {
    if (_lastPublishedLat == null || _lastPublishedLon == null) return true;
    return (lat - _lastPublishedLat!).abs() > _coordEpsilon ||
        (lon - _lastPublishedLon!).abs() > _coordEpsilon;
  }

  // ---------------------------------------------------------------
  // KAWALAN PAUSE (dipanggil oleh skrin Transmission)
  // ---------------------------------------------------------------

  /// Masuk skrin Transmission — tahan GPS-change publish.
  void pauseGps() {
    _gpsPaused = true;
    _modbusTransmissionActive = true;
    if (kDebugMode) debugPrint('⏸️ [Publish] GPS publish paused (Modbus active)');
  }

  /// Keluar skrin Transmission — sambung GPS-change publish.
  void resumeGps() {
    _gpsPaused = false;
    _modbusTransmissionActive = false;
    if (kDebugMode) debugPrint('▶️ [Publish] GPS publish resumed');
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
    if (now.difference(_lastGpsPublish) < _gpsMinGap) return false;
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
    Duration locTimeout = const Duration(seconds: 20),
    bool requireConnected = false,
  }) async {
    if (_gpsPaused) return false;
    if (requireConnected && !_mqtt.isConnected) return false;

    await _ensureMeta();

    var f = fix ?? _location.lastFix;
    if (f == null ||
        (f.accuracy != null &&
            f.accuracy! > LocationService.maxAcceptableAccuracyMeters)) {
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
  /// Strategi lokasi: utamakan lastFix dari stream (instant); one-shot getCurrentFix
  /// hanya bila lastFix tiada ([locTimeout]).
  /// Return true kalau publish dihantar; false kalau di-SKIP (tiada fix langsung).
  Future<bool> publishModbus({
    required List<dynamic> sensorData,
    String transmissionType = 'Unknown',
    Duration locTimeout = const Duration(seconds: 4),
  }) async {
    await _ensureMeta();
    // UTAMA: guna fix terkini dari stream (instant) — elak getCurrentPosition
    // yang lambat/timeout setiap RX. Stream dihidupkan oleh skrin transmission.
    LocationFix? fix = _location.lastFix;
    // Fallback: tiada lastFix langsung → cuba one-shot sekali.
    if (fix == null) {
      try {
        fix = await _location
            .getCurrentFix(timeout: locTimeout)
            .timeout(locTimeout, onTimeout: () => null);
      } catch (_) {
        fix = null;
      }
    }

    // KEPUTUSAN: tiada fix langsung → SKIP publish (jujur, jangan tipu KL).
    if (fix == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [Publish] Modbus skip — no GPS fix available');
      }
      return false;
    }

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
    Duration locTimeout = const Duration(seconds: 3),
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastExitPublish) < _exitPublishDebounce) {
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
    );

    if (kDebugMode) {
      debugPrint('📤 [Publish] exit snapshot ($exitContext) sensor=$sensors');
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
    final movingThreshold = 0.5; // m/s — selari home_screen
    final sendDt = DateTime.now().toString().substring(0, 19);

    final payload = <String, dynamic>{
      'data_type': 'MG',
      'node_id': _nodeId ?? 'unknown',
      'send_dt': sendDt,
      'status_live': 'online',
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
      debugPrint('📤 [Publish] bundle sent — sensor=$sensorData '
          'lat=${lat.toStringAsFixed(4)} lon=${lon.toStringAsFixed(4)} '
          'tx=$transmissionType connected=${_mqtt.isConnected}');
    }
  }

  /// Status sambungan (untuk UI indikator). Delegasi ke MqttService.
  bool get isMqttConnected => _mqtt.isConnected;
}