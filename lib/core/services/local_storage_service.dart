import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  SharedPreferences? _prefs;

  // Keys
  static const String _kAgencyToken = 'agency_token';
  static const String _kAgencyId = 'agency_id';
  static const String _kAgencyCode = 'agency_code';
  static const String _kAgencyName = 'agency_name';
  static const String _kDeviceName = 'device_name';
  static const String _kRegisteredDeviceId = 'registered_device_id';
  static const String _kOwnerData = 'owner_data';
  static const String _kSessionToken = 'session_token';
  static const String _kNeedApproval = 'need_approval';
  static const String _kModbusRxTimeoutMs = 'modbus_rx_timeout_ms';

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // --- Agency ---

  Future<void> saveAgencyToken(String token) async {
    final prefs = await _getPrefs();
    await prefs.setString(_kAgencyToken, token);
  }

  Future<String?> getAgencyToken() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kAgencyToken);
  }

  Future<bool> hasAgencyToken() async {
    final token = await getAgencyToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> saveAgencyId(int id) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_kAgencyId, id);
  }

  Future<int?> getAgencyId() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_kAgencyId);
  }

  Future<void> saveAgencyInfo({String? code, String? name}) async {
    final prefs = await _getPrefs();
    if (code != null) await prefs.setString(_kAgencyCode, code);
    if (name != null) await prefs.setString(_kAgencyName, name);
  }

  Future<String?> getAgencyCode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kAgencyCode);
  }

  Future<String?> getAgencyName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kAgencyName);
  }

  // --- Device info ---

  Future<void> saveDeviceInfo({
    required String deviceId,
    required String name,
  }) async {
    final prefs = await _getPrefs();
    await prefs.setString(_kRegisteredDeviceId, deviceId);
    await prefs.setString(_kDeviceName, name);
  }

  Future<Map<String, String>?> getDeviceInfo() async {
    final prefs = await _getPrefs();
    final deviceId = prefs.getString(_kRegisteredDeviceId);
    if (deviceId == null || deviceId.isEmpty) return null;
    final name = prefs.getString(_kDeviceName) ?? '';
    return {'device_id': deviceId, 'name': name};
  }

  Future<bool> hasDeviceInfo() async {
    final prefs = await _getPrefs();
    final deviceId = prefs.getString(_kRegisteredDeviceId);
    return deviceId != null && deviceId.isNotEmpty;
  }

  Future<String?> getDeviceName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kDeviceName);
  }

  /// Had tunggu jawapan Modbus RX (ms) — tetapan global, sekali dalam Settings.
  Future<int> getModbusRxTimeoutMs({int defaultMs = 1000}) async {
    final prefs = await _getPrefs();
    return prefs.getInt(_kModbusRxTimeoutMs) ?? defaultMs;
  }

  Future<void> saveModbusRxTimeoutMs(int ms) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_kModbusRxTimeoutMs, ms);
  }

  // --- Owner data (JSON) ---

  Future<void> saveOwnerData(Map<String, dynamic> data) async {
    final prefs = await _getPrefs();
    await prefs.setString(_kOwnerData, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getOwnerData() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kOwnerData);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('LocalStorageService: failed to decode owner_data');
      }
      return null;
    }
  }

  Future<bool> hasOwnerData() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kOwnerData);
    return raw != null && raw.isNotEmpty;
  }

  // --- Session + approval ---

  Future<void> saveSessionToken(String token) async {
    final prefs = await _getPrefs();
    await prefs.setString(_kSessionToken, token);
  }

  Future<String?> getSessionToken() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kSessionToken);
  }

  Future<void> saveNeedApproval(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_kNeedApproval, value);
  }

  Future<bool> getNeedApproval() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_kNeedApproval) ?? false;
  }

  /// Clear data agency SAHAJA (untuk tukar agency / re-provision).
  /// device_id (secure storage) & device info dikekalkan.
  Future<void> clearAgencyData() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_kAgencyToken),
      prefs.remove(_kAgencyId),
      prefs.remove(_kAgencyCode),
      prefs.remove(_kAgencyName),
      prefs.remove(_kNeedApproval),
    ]);
  }

  // --- Clear ---

  Future<void> clearAllData() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_kAgencyToken),
      prefs.remove(_kAgencyId),
      prefs.remove(_kAgencyCode),
      prefs.remove(_kAgencyName),
      prefs.remove(_kDeviceName),
      prefs.remove(_kRegisteredDeviceId),
      prefs.remove(_kOwnerData),
      prefs.remove(_kSessionToken),
      prefs.remove(_kNeedApproval),
      prefs.remove(_kModbusRxTimeoutMs),
    ]);
  }
}
