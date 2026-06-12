import 'location_service.dart';

// Kelas untuk menapis noise GPS
class GpsSmoother {
  final int windowSize;
  final List<LocationFix> _buffer = [];

  GpsSmoother(this.windowSize);

  void add(LocationFix fix) {
    if (_buffer.length >= windowSize) {
      _buffer.removeAt(0);
    }
    _buffer.add(fix);
  }

  LocationFix? getSmoothedFix() {
    if (_buffer.isEmpty) return null;

    double latSum = 0;
    double lonSum = 0;
    double speedSum = 0;
    double headingSum = 0;
    double accuracySum = 0;

    for (var fix in _buffer) {
      latSum += fix.latitude;
      lonSum += fix.longitude;
      speedSum += fix.speed;
      headingSum += fix.heading ?? 0;
      accuracySum += fix.accuracy ?? 0;
    }

    // Mengembalikan objek LocationFix purata
    // Anda mungkin perlu menyesuaikan constructor mengikut class LocationFix sebenar anda
    return LocationFix(
      latitude: latSum / _buffer.length,
      longitude: lonSum / _buffer.length,
      speed: speedSum / _buffer.length,
      heading: headingSum / _buffer.length,
      accuracy: accuracySum / _buffer.length,
    );
  }

  void clear() => _buffer.clear();
}