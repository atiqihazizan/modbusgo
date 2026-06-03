// modbus_storage_service.dart — Simpan senarai Modbus device (shared_preferences).
//
// NOTA: shared_preferences HILANG bila app uninstall (sama untuk Android & iOS).
// Untuk kekal selepas uninstall perlu storage luar sandbox (rumit) — di luar skop.
//
// Serialize field KONFIGURASI sahaja (bukan registerValues runtime).
// Check wujud guna 'address' (IP untuk WiFi, MAC untuk BT) + connectionType.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/home_screen/widgets/modbus_device_panel_widget.dart';

class ModbusStorageService {
  ModbusStorageService._internal();
  static final ModbusStorageService _instance =
      ModbusStorageService._internal();
  factory ModbusStorageService() => _instance;

  static const String _key = 'modbus_devices_v1';

  // ---------------------------------------------------------------
  // Serialize / deserialize satu device (config sahaja)
  // ---------------------------------------------------------------

  Map<String, dynamic> _toMap(ModbusDevice d) => {
        'id': d.id,
        'name': d.name,
        'address': d.address,
        'port': d.port,
        'connectionType': d.connectionType.name, // 'wifi' / 'bluetooth'
        'slaveId': d.slaveId,
        'functionCode': d.functionCode,
        'dataType': d.dataType,
        'byteOrder': d.byteOrder,
        'startAddress': d.startAddress,
        'registerCount': d.registerCount,
      };

  ModbusDevice _fromMap(Map<String, dynamic> m) => ModbusDevice(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? 'Device',
        address: m['address'] as String? ?? '',
        port: m['port'] as int? ?? 502,
        connectionType: (m['connectionType'] as String) == 'bluetooth'
            ? ModbusConnectionType.bluetooth
            : ModbusConnectionType.wifi,
        isConnected: false, // runtime, sentiasa false bila load
        slaveId: m['slaveId'] as int? ?? 1,
        functionCode: m['functionCode'] as String? ?? 'FC03',
        dataType: m['dataType'] as String? ?? 'INT16',
        byteOrder: m['byteOrder'] as String? ?? 'Big Endian',
        startAddress: m['startAddress'] as int? ?? 0,
        registerCount: m['registerCount'] as int? ?? 2,
        registerValues: const [],
      );

  // ---------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------

  /// Ambil semua device tersimpan. Pulang list kosong kalau tiada/ralat.
  Future<List<ModbusDevice>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _fromMap(e as Map<String, dynamic>))
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  /// Check wujud ikut address + connectionType (IP/MAC unik per jenis).
  /// Pulang true kalau dah ada.
  Future<bool> exists(
    String address,
    ModbusConnectionType type, {
    String? excludeId,
  }) async {
    final all = await getAll();
    return all.any((d) =>
        d.address.toLowerCase() == address.toLowerCase() &&
        d.connectionType == type &&
        d.id != excludeId);
  }

  /// Ambil satu device by id. Null kalau tiada.
  Future<ModbusDevice?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------

  Future<bool> _saveAll(List<ModbusDevice> devices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(devices.map(_toMap).toList());
      return prefs.setString(_key, raw);
    } catch (_) {
      return false;
    }
  }

  /// Tambah device baru. Pulang false kalau address+type dah wujud (duplicate).
  Future<bool> add(ModbusDevice device) async {
    if (await exists(device.address, device.connectionType)) return false;
    final all = await getAll();
    all.add(device);
    return _saveAll(all);
  }

  /// Kemaskini device sedia ada (by id). Pulang false kalau tak jumpa.
  Future<bool> update(ModbusDevice device) async {
    final all = await getAll();
    final idx = all.indexWhere((d) => d.id == device.id);
    if (idx == -1) return false;
    all[idx] = device;
    return _saveAll(all);
  }

  /// Tambah atau kemaskini (upsert) by id.
  Future<bool> upsert(ModbusDevice device) async {
    final all = await getAll();
    final idx = all.indexWhere((d) => d.id == device.id);
    if (idx == -1) {
      all.add(device);
    } else {
      all[idx] = device;
    }
    return _saveAll(all);
  }

  /// Buang device by id.
  Future<bool> remove(String id) async {
    final all = await getAll();
    all.removeWhere((d) => d.id == id);
    return _saveAll(all);
  }

  /// Kosongkan semua (untuk reset/debug).
  Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.remove(_key);
    } catch (_) {
      return false;
    }
  }
}