// Satu tempat untuk tuning publish GPS, idle, dan sensitiviti jarak/koordinat.

abstract final class TrackingPublishConfig {
  // --- status_live (bundle tracking) ---
  static const String statusLiveOnline = 'online';
  static const String statusLiveIdle = 'idle';
  static const String statusLiveOffline = 'offline';

  // --- Idle / publish timing (idle watchdog & heartbeat — logik guna nilai ini) ---
  static const Duration idleWatchAfterPublish = Duration(seconds: 10);
  static const Duration idleHeartbeatInterval = Duration(seconds: 3);
  static const Duration gpsChangeMinGap = Duration(seconds: 3);
  static const Duration exitPublishDebounce = Duration(seconds: 4);

  // --- Distance sensitivity ---
  /// Perbezaan min lat/lon (darjah) untuk anggap koordinat "berubah".
  static const double coordinateChangeEpsilonDegrees = 5e-5;

  /// Geolocator: emit fix bila pergerakan ≥ meter ini.
  static const int locationDistanceFilterMeters = 5;

  /// Tolak fix dengan accuracy lebih buruk daripada ini (meter).
  static const double maxAcceptableAccuracyMeters = 80;

  // --- motion_status (kelajuan, bukan status_live) ---
  static const double motionMovingSpeedThresholdMps = 0.5;

  // --- Timeout one-shot lokasi dalam PublishService ---
  static const Duration locationTimeoutSnapshot = Duration(seconds: 20);
  static const Duration locationTimeoutModbus = Duration(seconds: 4);
  static const Duration locationTimeoutExit = Duration(seconds: 3);

  /// Default [LocationService.getCurrentFix] bila pemanggil tidak pass timeout.
  static const Duration locationTimeoutDefault = locationTimeoutSnapshot;

  /// Saiz langkah poll dalaman [LocationService.getCurrentFix].
  static const Duration locationOneShotPollChunkMax = Duration(seconds: 12);
  static const Duration locationOneShotPollChunkMin = Duration(seconds: 8);
}
