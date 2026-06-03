// PublishService — PINTU TUNGGAL untuk semua publish tracking bundle.
//
// Reka bentuk (disahkan dengan keputusan projek):
//   - Mutually exclusive: Modbus (dalam skrin Transmission) ATAU GPS (luar skrin).
//   - Masuk skrin Transmission → pauseGps(): GPS-change publish ditahan.
//   - Keluar skrin Transmission → resumeGps(): GPS-change publish sambung semula.
//   - Data Modbus masuk → publishModbus(): baca lat/lon segar, publish sensor sebenar.
//   - GPS berubah (luar skrin) → publishGps(): sensor_data [-1] (tiada data sensor).
//
// Service ini TIDAK menggantikan MqttService/LocationService — ia membungkus
// keduanya supaya logik bina-payload + kawalan pause berada di SATU tempat.
//
// Payload kekal padan backend v3 (lihat MqttService.publishBundle):
//   {data_type:'MG', latitude, longitude, speed, heading?, sensor_data:[...]}
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'device_identity_service.dart';
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

  // Throttle GPS publish — elak spam bila fix masuk laju. Modbus TIDAK di-throttle
  // di sini sebab kadarnya dikawal oleh polling loop transport.
  DateTime _lastGpsPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _gpsMinGap = Duration(seconds: 3);

  // ---------------------------------------------------------------
  // KAWALAN PAUSE (dipanggil oleh skrin Transmission)
  // ---------------------------------------------------------------

  /// Masuk skrin Transmission — tahan GPS-change publish.
  void pauseGps() {
    _gpsPaused = true;
    if (kDebugMode) debugPrint('⏸️ [Publish] GPS publish paused (Modbus aktif)');
  }

  /// Keluar skrin Transmission — sambung GPS-change publish.
  void resumeGps() {
    _gpsPaused = false;
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

  /// Publish manual (butang emit / refresh GPS). Abaikan pause & throttle —
  /// user minta hantar terus. Guna lastFix kalau ada, fallback null-safe.
  void publishManual({LocationFix? fix}) {
    final f = fix ?? _location.lastFix;
    _publish(
      latitude: f?.latitude,
      longitude: f?.longitude,
      speed: f?.speed ?? 0,
      heading: f?.heading,
      sensorData: const [-1],
    );
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
        debugPrint('⚠️ [Publish] Modbus skip — tiada GPS fix langsung');
      }
      return false;
    }

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
    // Fallback koordinat ikut corak sedia ada (KL) bila tiada fix langsung.
    final lat = latitude ?? 3.1390;
    final lon = longitude ?? 101.6869;
    final movingThreshold = 0.5; // m/s — selari home_screen
    final sendDt = DateTime.now().toString().substring(0, 19);

    final payload = <String, dynamic>{
      'data_type': 'MG',
      'node_id': _nodeId ?? 'unknown',
      'send_dt': sendDt,
      'status_live': 'online',
      'motion_status': speed > movingThreshold ? 'moving' : 'idle',
      'speed': speed,
      if (heading != null) 'heading': heading,
      'cpu_temp': 0.0, // telefon tak dedah suhu CPU sebenar
      'latitude': lat,
      'longitude': lon,
      'battery_level': 0, // skip buat masa ni
      'transmission_type': transmissionType,
      'sensor_data': sensorData,
      'name': _deviceName ?? _nodeId ?? 'unknown',
      if (_sessionToken != null) 'session_token': _sessionToken,
    };

    _mqtt.publishBundle(payload);

    if (kDebugMode) {
      debugPrint('📤 [Publish] bundle sent — sensor=$sensorData '
          'lat=${lat.toStringAsFixed(4)} lon=${lon.toStringAsFixed(4)} '
          'tx=$transmissionType connected=${_mqtt.isConnected}');
    }
  }

  /// Status sambungan (untuk UI indikator). Delegasi ke MqttService.
  bool get isMqttConnected => _mqtt.isConnected;
}