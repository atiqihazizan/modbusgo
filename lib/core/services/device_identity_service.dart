import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import './device_identity_storage.dart';
import './secure_storage_backend.dart';

/// Stable device identity.
/// - Android: guna androidInfo.id (kekal merentas uninstall, tiada storage perlu).
/// - iOS: UUID dalam Keychain (kekal selepas uninstall; iOS sekat ID awam).
class DeviceIdentityService {
  static const String _kDeviceIdKey = 'device_id';

  static final DeviceIdentityService _instance =
      DeviceIdentityService._internal();

  final DeviceIdentityStorage _storage;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  String? _cachedId;

  factory DeviceIdentityService({DeviceIdentityStorage? storage}) {
    if (storage != null) {
      return DeviceIdentityService._withStorage(storage);
    }
    return _instance;
  }

  DeviceIdentityService._internal() : _storage = SecureStorageBackend();
  DeviceIdentityService._withStorage(this._storage);

  /// Returns the stable device ID.
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    // Android: guna system id terus.
    if (!kIsWeb && Platform.isAndroid) {
      _cachedId = await _getAndroidDeviceId();
      return _cachedId!;
    }

    // iOS (dan lain-lain): UUID dalam Keychain.
    _cachedId = await _getOrCreateUuid();
    return _cachedId!;
  }

  Future<String> _getAndroidDeviceId() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      if (androidInfo.id.isNotEmpty) {
        return androidInfo.id;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Android ID not available: $e');
    }
    // Fallback: UUID (jarang berlaku).
    return _getOrCreateUuid();
  }

  /// iOS / fallback — baca UUID dari Keychain; jana + simpan kalau tiada.
  Future<String> _getOrCreateUuid() async {
    try {
      final stored = await _storage.read(_kDeviceIdKey);
      if (stored != null && stored.isNotEmpty) {
        return stored;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeviceIdentityService: read error — $e');
    }

    final newId = const Uuid().v4();
    try {
      await _storage.write(_kDeviceIdKey, newId);
    } catch (e) {
      if (kDebugMode) debugPrint('DeviceIdentityService: write error — $e');
    }
    return newId;
  }

  /// For testing only.
  Future<void> resetDeviceId() async {
    await _storage.delete(_kDeviceIdKey);
    _cachedId = null;
  }
}