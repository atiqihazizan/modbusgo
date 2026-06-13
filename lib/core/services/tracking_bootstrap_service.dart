// TrackingBootstrapService — bootstrap GPS + MQTT + publish scheduler di peringkat app.
// Idempotent; retry automatik jika GPS/permission belum ready.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_identity_service.dart';
import 'local_storage_service.dart';
import 'location_service.dart';
import 'mqtt_service.dart';
import 'publish_service.dart';

class TrackingBootstrapService {
  TrackingBootstrapService._internal();
  static final TrackingBootstrapService _instance =
      TrackingBootstrapService._internal();
  factory TrackingBootstrapService() => _instance;

  static const Duration _retryInterval = Duration(seconds: 5);
  static const int _maxRetries = 12;

  bool _gpsStarted = false;
  Future<void>? _inFlight;
  int _retryCount = 0;
  Timer? _retryTimer;

  bool get isGpsStarted => _gpsStarted;

  /// Mulakan tracking jika peranti sudah didaftarkan (idempotent + retry).
  /// Panggilan serentak kongsi Future yang sama — elak connect MQTT berganda.
  Future<void> startIfRegistered() {
    return _inFlight ??= _startIfRegisteredBody().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _startIfRegisteredBody() async {
    final storage = LocalStorageService();
    if (!await storage.isRegisteredLocally()) {
      _cancelRetry();
      if (kDebugMode) {
        debugPrint('🛰️ [TrackingBootstrap] skip — device not registered');
      }
      return;
    }

    final deviceId = await DeviceIdentityService().getDeviceId();
    if (deviceId.isEmpty) {
      if (kDebugMode) {
        debugPrint('🛰️ [TrackingBootstrap] skip — empty device id');
      }
      return;
    }

    if (!_gpsStarted) {
      _gpsStarted = await LocationService().start();
    }
    await MqttService().init(deviceId: deviceId);
    PublishService().startScheduler();

    if (_gpsStarted) {
      _retryCount = 0;
      _cancelRetry();
      if (kDebugMode) {
        debugPrint('🛰️ [TrackingBootstrap] started (GPS + MQTT + scheduler)');
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          '🛰️ [TrackingBootstrap] GPS not ready — '
          'MQTT/scheduler up, will retry GPS',
        );
      }
      _scheduleRetry();
    }
  }

  /// Dipanggil bila app kembali foreground.
  void onAppResumed() {
    _retryCount = 0;
    MqttService().resumeReconnect();
    PublishService().startScheduler();
    unawaited(startIfRegistered());
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _retryCount >= _maxRetries) return;
    _retryTimer = Timer(_retryInterval, () {
      _retryTimer = null;
      _retryCount++;
      unawaited(startIfRegistered());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
