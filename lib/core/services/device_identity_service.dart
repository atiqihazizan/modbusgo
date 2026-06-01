import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import './device_identity_storage.dart';
import './secure_storage_backend.dart';

/// Singleton service that generates and persists a stable device UUID.
class DeviceIdentityService {
  static const String _kDeviceIdKey = 'device_id';

  static final DeviceIdentityService _instance =
      DeviceIdentityService._internal();

  final DeviceIdentityStorage _storage;
  String? _cachedId;

  factory DeviceIdentityService({DeviceIdentityStorage? storage}) {
    if (storage != null) {
      return DeviceIdentityService._withStorage(storage);
    }
    return _instance;
  }

  DeviceIdentityService._internal() : _storage = SecureStorageBackend();

  DeviceIdentityService._withStorage(this._storage);

  /// Returns the persisted device ID, generating one on first call.
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final stored = await _storage.read(_kDeviceIdKey);
      if (stored != null && stored.isNotEmpty) {
        _cachedId = stored;
        return _cachedId!;
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
    _cachedId = newId;
    return _cachedId!;
  }

  /// Deletes the stored device ID and clears the cache. For testing only.
  Future<void> resetDeviceId() async {
    await _storage.delete(_kDeviceIdKey);
    _cachedId = null;
  }
}
