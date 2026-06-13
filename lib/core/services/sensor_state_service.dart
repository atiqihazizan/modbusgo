// SensorStateService — singleton cache sensor state terkini untuk GPS/backfill publish.
// Setiap publish GPS melampirkan snapshot semasa — bukan hardcode [-1].
import 'package:flutter/foundation.dart';

class SensorStateService {
  SensorStateService._internal();
  static final SensorStateService _instance = SensorStateService._internal();
  factory SensorStateService() => _instance;

  List<dynamic> _payload = const [];
  String _transmissionType = 'GPS';

  List<dynamic> get payload => List<dynamic>.from(_payload);
  String get transmissionType => _transmissionType;
  bool get hasData => _payload.isNotEmpty;

  /// Kemas kini state sensor (Modbus RX, skrin Transmission, dll.).
  void update({
    required List<dynamic> sensorData,
    required String transmissionType,
  }) {
    _payload = List<dynamic>.from(sensorData);
    _transmissionType = transmissionType;
    if (kDebugMode) {
      debugPrint(
        '📊 [SensorState] updated tx=$transmissionType data=$_payload',
      );
    }
  }

  /// Salinan untuk lampir pada setiap GPS event / publish.
  SensorSnapshot snapshot() {
    return SensorSnapshot(
      sensorData: List<dynamic>.from(_payload),
      transmissionType: _transmissionType,
    );
  }
}

class SensorSnapshot {
  const SensorSnapshot({
    required this.sensorData,
    required this.transmissionType,
  });

  final List<dynamic> sensorData;
  final String transmissionType;
}
