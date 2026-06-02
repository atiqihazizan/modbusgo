import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import './api_client.dart';
import './device_identity_service.dart';
import './local_storage_service.dart';

// Registration — register device + check (restore after reinstall).
// register: POST /devices-user/register  (header x-agency-token)
// check:    GET  /devices-user/check/:deviceid  (public)

class CheckResult {
  final bool exists;
  final Map<String, dynamic>? device; // raw device map from backend
  const CheckResult({required this.exists, this.device});
}

class RegisterResult {
  final bool success;
  final bool isNew;
  final bool needApproval;
  final String? deviceId;
  final String? name;
  final String? agencyToken;
  final int? agencyId;
  final String? agencyName;
  const RegisterResult({
    required this.success,
    this.isNew = false,
    this.needApproval = false,
    this.deviceId,
    this.name,
    this.agencyToken,
    this.agencyId,
    this.agencyName,
  });
}

class RegistrationService {
  RegistrationService._internal();
  static final RegistrationService _instance = RegistrationService._internal();
  factory RegistrationService() => _instance;

  final ApiClient _api = ApiClient();
  final LocalStorageService _storage = LocalStorageService();
  final DeviceIdentityService _identity = DeviceIdentityService();

  // Restore check after reinstall. Returns null on network/parse failure.
  Future<CheckResult?> checkDevice([String? deviceId]) async {
    try {
      final id = deviceId ?? await _identity.getDeviceId();
      final res = await _api.dio.get('/devices-user/check/$id');

      if (res.statusCode == 200 && res.data is Map) {
        final body = res.data as Map;
        final exists = body['exists'] == true;
        final device = body['device'] is Map
            ? Map<String, dynamic>.from(body['device'] as Map)
            : null;
        return CheckResult(exists: exists, device: device);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[Registration] checkDevice error: $e');
      return null;
    }
  }

  // Register device with current agency_token. Returns success=false on any failure.
  // Register device with current agency_token. Returns success=false on any failure.
  Future<RegisterResult> registerDevice({required String name}) async {
    try {
      final token = await _storage.getAgencyToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          print('[Registration] no agency_token — provision first');
        }
        return const RegisterResult(success: false);
      }

      final deviceId = await _identity.getDeviceId();
      final res = await _api.dio.post(
        '/devices-user/register',
        data: {'device_id': deviceId, 'name': name},
        options: Options(headers: {'x-agency-token': token}),
      );

      final ok =
          (res.statusCode == 200 || res.statusCode == 201) &&
          res.data is Map &&
          res.data['success'] == true;

      if (!ok) {
        if (kDebugMode) {
          print('[Registration] failed: ${res.statusCode} ${res.data}');
        }
        return const RegisterResult(success: false);
      }

      final body = res.data as Map;
      final device = body['device'] is Map ? body['device'] as Map : const {};
      final needApproval = body['need_approval'] == true;
      final isNew = body['is_new'] == true;
      final respToken = body['agency_token'] as String?;
      final agencyId = body['agency_id'] is int
          ? body['agency_id'] as int
          : null;
      final agencyCode = body['agency_code'] as String?;
      final agencyName = body['agency_name'] as String?;

      // Persist confirmed state.
      await _storage.saveDeviceInfo(
        deviceId: deviceId,
        name: (device['name'] ?? name).toString(),
      );
      await _storage.saveNeedApproval(needApproval);
      if (respToken != null && respToken.isNotEmpty) {
        await _storage.saveAgencyToken(respToken);
      }
      if (agencyId != null) await _storage.saveAgencyId(agencyId);
      await _storage.saveAgencyInfo(code: agencyCode, name: agencyName);

      return RegisterResult(
        success: true,
        isNew: isNew,
        needApproval: needApproval,
        deviceId: deviceId,
        name: (device['name'] ?? name).toString(),
        agencyToken: respToken,
        agencyId: agencyId,
        agencyName: agencyName,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Registration] DioException: ${e.message}');
      return const RegisterResult(success: false);
    } catch (e) {
      if (kDebugMode) print('[Registration] error: $e');
      return const RegisterResult(success: false);
    }
  }

  // After reinstall: restore agency_token + device info from /check.
  Future<bool> restoreFromBackend() async {
    final result = await checkDevice();
    if (result == null || !result.exists || result.device == null) return false;

    final d = result.device!;
    final token = d['agency_token'] as String?;
    final name = d['name'] as String?;
    final agencyId = d['agency_id'] is int ? d['agency_id'] as int : null;
    final agencyCode = d['agency_code'] as String?;
    final agencyName = d['agency_name'] as String?;
    final needApproval = d['need_approval'] == true;

    if (token != null && token.isNotEmpty) {
      await _storage.saveAgencyToken(token);
    }
    if (agencyId != null) await _storage.saveAgencyId(agencyId);
    await _storage.saveAgencyInfo(code: agencyCode, name: agencyName);
    if (name != null) {
      final id = await _identity.getDeviceId();
      await _storage.saveDeviceInfo(deviceId: id, name: name);
    }
    await _storage.saveNeedApproval(needApproval);
    return true;
  }
}
