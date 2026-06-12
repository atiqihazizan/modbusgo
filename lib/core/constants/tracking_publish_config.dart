// Satu tempat untuk tuning publish GPS, idle, dan sensitiviti jarak/koordinat.

abstract final class TrackingPublishConfig {
  // --- status_live (bundle tracking) ---
  static const String statusLiveOnline = 'online';
  static const String statusLiveIdle = 'idle';
  static const String statusLiveOffline = 'offline';

  // --- Scheduler (ticker pusat GPS + Modbus) ---
  /// Interval tik scheduler — mudah ubah (default 500ms).
  // static const Duration schedulerTickInterval = Duration(milliseconds: 500);
  static const Duration schedulerTickInterval = Duration(seconds: 1);

  // --- Publish timing ---
  static const Duration gpsChangeMinGap = Duration(seconds: 1);
  static const Duration maxPublishInterval = Duration(seconds: 5);
  static const Duration idleHeartbeatInterval = Duration(seconds: 30);
  static const Duration idleConfirmDuration = Duration(seconds: 60);
  static const Duration exitPublishDebounce = Duration(seconds: 1);

  // --- Distance sensitivity (meter) ---
  /// Jarak min untuk anggap bergerak / layak publish online.
  static const double minMoveDistanceMeters = 1;

  /// Jarak di bawah ini = koordinat redundant (skip publish online).
  // static const double redundantDistanceMeters = 2;
  static const double redundantDistanceMeters = 5;

  /// Geolocator: emit fix bila pergerakan ≥ meter ini.
  static const int locationDistanceFilterMeters = 1;

  /// Tolak fix dengan accuracy lebih buruk daripada ini (meter).
  // static const double maxAcceptableAccuracyMeters = 80;
  static const double maxAcceptableAccuracyMeters = 15;

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
