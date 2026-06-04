// LocationService — GPS via geolocator.
// - getCurrentFix(): one-shot fix (untuk provisioning, WAJIB ada).
// - start()/stream: aliran lokasi berterusan (untuk tracking, non-blocking).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/tracking_publish_config.dart';

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

  LocationSettings _streamSettings() {
    final filter = TrackingPublishConfig.locationDistanceFilterMeters;
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: filter,
        forceLocationManager: true,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: filter,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: filter,
    );
  }

  LocationSettings _oneShotSettings(Duration timeout) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: timeout,
        forceLocationManager: true,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: timeout,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.best,
      timeLimit: timeout,
    );
  }

  LocationFix _fixFromPosition(Position pos) {
    return LocationFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      speed: pos.speed.isNaN ? 0 : pos.speed,
      heading: pos.heading.isNaN ? null : pos.heading,
      accuracy: pos.accuracy,
    );
  }

  bool _accuracyOk(Position pos) {
    final acc = pos.accuracy;
    if (acc.isNaN || acc < 0) return true;
    return acc <= TrackingPublishConfig.maxAcceptableAccuracyMeters;
  }

  /// Pastikan servis lokasi hidup + permission diberi.
  /// Return null kalau OK; return mesej error kalau gagal.
  Future<String?> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Please turn on GPS.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Please enable it in Settings.';
    }
    if (!kIsWeb && Platform.isAndroid) {
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Pastikan fine location (bukan coarse sahaja) pada Android 12+.
        final precise = await Geolocator.getLocationAccuracy();
        if (precise == LocationAccuracyStatus.reduced) {
          return 'Precise location is off. Please enable "Precise location" in Settings.';
        }
      }
    }
    return null;
  }

  /// One-shot fix untuk provisioning. WAJIB ada — kalau gagal, return null.
  /// [timeout] had masa tunggu fix.
  Future<LocationFix?> getCurrentFix({
    Duration timeout = TrackingPublishConfig.locationTimeoutDefault,
  }) async {
    final err = await ensureReady();
    if (err != null) {
      if (kDebugMode) debugPrint('📍 [Location] ensureReady failed: $err');
      return null;
    }
    try {
      final deadline = DateTime.now().add(timeout);
      Position? best;
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _oneShotSettings(
            remaining < TrackingPublishConfig.locationOneShotPollChunkMin
                ? remaining
                : TrackingPublishConfig.locationOneShotPollChunkMax,
          ),
        );
        if (best == null || pos.accuracy < best.accuracy) {
          best = pos;
        }
        if (_accuracyOk(pos)) {
          final fix = _fixFromPosition(pos);
          _last = fix;
          return fix;
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (best != null) {
        if (kDebugMode) {
          debugPrint(
            '📍 [Location] using best fix (accuracy=${best.accuracy.toStringAsFixed(0)}m)',
          );
        }
        final fix = _fixFromPosition(best);
        _last = fix;
        return fix;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('📍 [Location] getCurrentFix failed: $e');
      return null;
    }
  }

  /// Mula aliran lokasi berterusan (untuk home/tracking). Non-blocking.
  Future<void> start() async {
    final err = await ensureReady();
    if (err != null) {
      if (kDebugMode) debugPrint('📍 [Location] start cancelled: $err');
      return;
    }
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _streamSettings())
        .listen(
      (pos) {
        if (!_accuracyOk(pos)) {
          if (kDebugMode) {
            debugPrint(
              '📍 [Location] skip coarse fix accuracy=${pos.accuracy.toStringAsFixed(0)}m',
            );
          }
          return;
        }
        final fix = _fixFromPosition(pos);
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
