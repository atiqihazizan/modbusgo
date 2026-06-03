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

import 'location_service.dart';
import 'mqtt_service.dart';

class PublishService {
  PublishService._internal();
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;

  final MqttService _mqtt = MqttService();
  final LocationService _location = LocationService();

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
  /// Strategi lokasi: cuba getCurrentFix() segar (had [locTimeout]); kalau gagal
  /// atau lambat, fallback ke lastFix supaya publish tak tergantung.
  /// Return true kalau publish dihantar; false kalau di-SKIP (tiada fix langsung).
  Future<bool> publishModbus({
    required List<dynamic> sensorData,
    Duration locTimeout = const Duration(seconds: 4),
  }) async {
    LocationFix? fix;
    try {
      fix = await _location
          .getCurrentFix(timeout: locTimeout)
          .timeout(locTimeout, onTimeout: () => null);
    } catch (_) {
      fix = null;
    }
    // Fallback: fix segar gagal → guna fix terakhir diketahui.
    fix ??= _location.lastFix;

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
  }) {
    // Fallback koordinat ikut corak sedia ada (KL) bila tiada fix langsung.
    final lat = latitude ?? 3.1390;
    final lon = longitude ?? 101.6869;

    _mqtt.publishBundle({
      'data_type': 'MG',
      'latitude': lat,
      'longitude': lon,
      'speed': speed,
      if (heading != null) 'heading': heading,
      'sensor_data': sensorData,
    });

    if (kDebugMode) {
      debugPrint('📤 [Publish] bundle sent — sensor=$sensorData '
          'lat=${lat.toStringAsFixed(4)} lon=${lon.toStringAsFixed(4)} '
          'connected=${_mqtt.isConnected}');
    }
  }

  /// Status sambungan (untuk UI indikator). Delegasi ke MqttService.
  bool get isMqttConnected => _mqtt.isConnected;
}