// modbus_runtime_service.dart — Simpan runtime data Modbus per device.
//
// - Register values + log TX/RX (max 10) kekal dalam shared_preferences
//   sehingga app uninstall.
// - Home papar register values semasa polling aktif sahaja.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/home_screen/widgets/modbus_device_panel_widget.dart';
import '../constants/modbus_data_format.dart';

/// Satu entri log TX/RX.
class TxRxLogEntry {
  final bool isTx;
  final String data;
  final DateTime time;
  final bool isError;

  const TxRxLogEntry({
    required this.isTx,
    required this.data,
    required this.time,
    this.isError = false,
  });

  Map<String, dynamic> toMap() => {
        'isTx': isTx,
        'data': data,
        'time': time.toIso8601String(),
        'isError': isError,
      };

  factory TxRxLogEntry.fromMap(Map<String, dynamic> m) => TxRxLogEntry(
        isTx: m['isTx'] as bool? ?? false,
        data: m['data'] as String? ?? '',
        time: DateTime.tryParse(m['time'] as String? ?? '') ?? DateTime.now(),
        isError: m['isError'] as bool? ?? false,
      );
}

class ModbusDeviceRuntimeSnapshot {
  final List<num> registerNums;
  final List<TxRxLogEntry> txRxLog;

  const ModbusDeviceRuntimeSnapshot({
    this.registerNums = const [],
    this.txRxLog = const [],
  });

  Map<String, dynamic> toMap() => {
        'registerNums': registerNums,
        'txRxLog': txRxLog.map((e) => e.toMap()).toList(),
      };

  factory ModbusDeviceRuntimeSnapshot.fromMap(Map<String, dynamic> m) {
    final rawNums = m['registerNums'] as List<dynamic>? ?? const [];
    final rawLogs = m['txRxLog'] as List<dynamic>? ?? const [];
    return ModbusDeviceRuntimeSnapshot(
      registerNums: rawNums.map((e) => e as num).toList(growable: false),
      txRxLog: rawLogs
          .map((e) => TxRxLogEntry.fromMap(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// Singleton: cache memori + persist SharedPreferences.
class ModbusRuntimeService extends ChangeNotifier {
  ModbusRuntimeService._internal();
  static final ModbusRuntimeService _instance = ModbusRuntimeService._internal();
  factory ModbusRuntimeService() => _instance;

  static const String _key = 'modbus_runtime_v1';
  static const int maxLogEntries = 10;

  final Map<String, ModbusDeviceRuntimeSnapshot> _cache = {};
  String? _pollingDeviceId;
  bool _loaded = false;

  String? get pollingDeviceId => _pollingDeviceId;

  bool isPolling(String deviceId) => _pollingDeviceId == deviceId;

  /// Register values untuk paparan home — hanya semasa polling aktif.
  List<ModbusRegisterValue> liveRegisterValues(ModbusDevice device) {
    if (!isPolling(device.id)) return const [];
    final nums = _cache[device.id]?.registerNums ?? const [];
    if (nums.isEmpty) return const [];
    return registerNumsToDisplay(
      nums,
      startAddress: device.startAddress,
      dataType: device.dataType,
    );
  }

  List<num> registerNums(String deviceId) =>
      _cache[deviceId]?.registerNums ?? const [];

  List<TxRxLogEntry> txRxLog(String deviceId) =>
      _cache[deviceId]?.txRxLog ?? const [];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((id, value) {
          _cache[id] = ModbusDeviceRuntimeSnapshot.fromMap(
            value as Map<String, dynamic>,
          );
        });
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _cache.map((id, snap) => MapEntry(id, snap.toMap())),
      );
      await prefs.setString(_key, encoded);
    } catch (_) {}
  }

  ModbusDeviceRuntimeSnapshot _snapshotOrEmpty(String deviceId) =>
      _cache[deviceId] ?? const ModbusDeviceRuntimeSnapshot();

  void setPolling(String? deviceId) {
    if (_pollingDeviceId == deviceId) return;
    _pollingDeviceId = deviceId;
    notifyListeners();
  }

  Future<void> saveRegisterNums(String deviceId, List<num> values) async {
    await ensureLoaded();
    final prev = _snapshotOrEmpty(deviceId);
    _cache[deviceId] = ModbusDeviceRuntimeSnapshot(
      registerNums: List<num>.from(values),
      txRxLog: prev.txRxLog,
    );
    await _persist();
    if (isPolling(deviceId)) notifyListeners();
  }

  Future<void> appendLog(String deviceId, TxRxLogEntry entry) async {
    await ensureLoaded();
    final prev = _snapshotOrEmpty(deviceId);
    final logs = [entry, ...prev.txRxLog];
    if (logs.length > maxLogEntries) {
      logs.removeRange(maxLogEntries, logs.length);
    }
    _cache[deviceId] = ModbusDeviceRuntimeSnapshot(
      registerNums: prev.registerNums,
      txRxLog: logs,
    );
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    await ensureLoaded();
    if (!_cache.containsKey(deviceId)) return;
    _cache.remove(deviceId);
    if (_pollingDeviceId == deviceId) _pollingDeviceId = null;
    await _persist();
    notifyListeners();
  }

  Future<ModbusDeviceRuntimeSnapshot?> loadSnapshot(String deviceId) async {
    await ensureLoaded();
    return _cache[deviceId];
  }
}

List<ModbusRegisterValue> registerNumsToDisplay(
  List<num> values, {
  required int startAddress,
  required String dataType,
}) {
  return values.asMap().entries.map((e) {
    final addr = startAddress + e.key;
    return ModbusRegisterValue(
      address:
          '0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      value: formatRegisterValueForDisplay(e.value, dataType),
    );
  }).toList(growable: false);
}
