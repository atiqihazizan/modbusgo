// LocationService — GPS via geolocator.
// - getCurrentFix(): one-shot fix (untuk provisioning, WAJIB ada).
// - start()/stream: aliran lokasi berterusan (untuk tracking, non-blocking).
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.speed = 0,
    this.heading,
    this.accuracy,
  });
  final double latitude;
  final double longitude;
  final double speed;
  final double? heading;
  final double? accuracy;
}

class LocationService {
  LocationService._internal();
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  StreamSubscription<Position>? _sub;
  LocationFix? _last;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();

  Stream<LocationFix> get stream => _controller.stream;
  LocationFix? get lastFix => _last;

  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  /// Pastikan servis lokasi hidup + permission diberi.
  /// Return null kalau OK; return mesej error kalau gagal.
  Future<String?> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Sila hidupkan GPS.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Sila benarkan dalam tetapan.';
    }
    return null;
  }

  /// One-shot fix untuk provisioning. WAJIB ada — kalau gagal, return null.
  /// [timeout] had masa tunggu fix.
  Future<LocationFix?> getCurrentFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final err = await ensureReady();
    if (err != null) {
      if (kDebugMode) debugPrint('📍 [Location] ensureReady gagal: $err');
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      final fix = LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        speed: pos.speed.isNaN ? 0 : pos.speed,
        heading: pos.heading.isNaN ? null : pos.heading,
        accuracy: pos.accuracy,
      );
      _last = fix;
      return fix;
    } catch (e) {
      if (kDebugMode) debugPrint('📍 [Location] getCurrentFix gagal: $e');
      return null;
    }
  }

  /// Mula aliran lokasi berterusan (untuk home/tracking). Non-blocking.
  Future<void> start() async {
    final err = await ensureReady();
    if (err != null) {
      if (kDebugMode) debugPrint('📍 [Location] start dibatalkan: $err');
      return;
    }
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings).listen(
      (pos) {
        final fix = LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          speed: pos.speed.isNaN ? 0 : pos.speed,
          heading: pos.heading.isNaN ? null : pos.heading,
          accuracy: pos.accuracy,
        );
        _last = fix;
        if (!_controller.isClosed) _controller.add(fix);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('📍 [Location] stream error: $e');
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
