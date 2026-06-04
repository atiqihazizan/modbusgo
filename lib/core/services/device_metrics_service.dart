// DeviceMetricsService — cache bateri + suhu/thermal untuk payload MQTT.
// Nilai dan unit dihantar sebagai medan berasingan (lihat [buildPayloadFields]).
import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:thermal/thermal.dart';

import '../constants/metric_units.dart';

class DeviceMetricsService {
  DeviceMetricsService._internal();
  static final DeviceMetricsService _instance = DeviceMetricsService._internal();
  factory DeviceMetricsService() => _instance;

  final Battery _battery = Battery();
  final Thermal _thermal = Thermal();

  bool _started = false;
  StreamSubscription<BatteryState>? _batteryStateSub;
  StreamSubscription<double>? _batteryTempSub;
  StreamSubscription<ThermalStatus>? _thermalStatusSub;

  int? _batteryLevelPercent;
  double? _deviceTempCelsius;
  ThermalStatus? _thermalStatus;

  int? get batteryLevelPercent => _batteryLevelPercent;
  double? get deviceTempCelsius => _deviceTempCelsius;
  ThermalStatus? get thermalStatus => _thermalStatus;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshBattery();
    _batteryStateSub =
        _battery.onBatteryStateChanged.listen((_) => refreshBattery());

    _thermalStatusSub = _thermal.onThermalStatusChanged.listen((status) {
      _thermalStatus = status;
    });

    if (!kIsWeb && Platform.isAndroid) {
      _batteryTempSub = _thermal.onBatteryTemperatureChanged.listen((celsius) {
        _deviceTempCelsius = celsius;
      });
    }

    if (kDebugMode) {
      debugPrint('📊 [Metrics] started — battery=$_batteryLevelPercent '
          'tempC=$_deviceTempCelsius thermal=$_thermalStatus');
    }
  }

  Future<void> refreshBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (level >= 0 && level <= 100) {
        _batteryLevelPercent = level;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [Metrics] battery: $e');
    }
  }

  /// Medan payload: nilai + `*_unit` berasingan; tiada string gabungan.
  Map<String, dynamic> buildPayloadFields() {
    final fields = <String, dynamic>{
      'battery_level_unit': MetricUnits.percent,
      'cpu_temp_unit': MetricUnits.celsius,
    };

    if (_batteryLevelPercent != null) {
      fields['battery_level'] = _batteryLevelPercent;
    }

    if (_deviceTempCelsius != null) {
      fields['cpu_temp'] = _deviceTempCelsius;
    } else if (_thermalStatus != null &&
        _thermalStatus != ThermalStatus.none) {
      fields['thermal_status'] = _thermalStatus!.name;
      fields['thermal_status_unit'] = MetricUnits.thermalStatus;
    }

    return fields;
  }

  void dispose() {
    _batteryStateSub?.cancel();
    _batteryTempSub?.cancel();
    _thermalStatusSub?.cancel();
    _started = false;
  }
}
