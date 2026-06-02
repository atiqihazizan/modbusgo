import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import './api_client.dart';
import './local_storage_service.dart';

// Provisioning — redeem agency_token from scanned QR deep link.
// QR deep link form: modbusgo://provision?payload=<encryptedHex>
// Flutter does NOT decrypt — backend /provision/verify does. No AES key in app.

enum ProvisionError {
  invalidLink,
  network,
  decryptionFailed,
  payloadExpired,
  agencyNotFound,
  agencyInactive,
  tokenExpired,
  nonceMismatch,
  unknown,
}

class ProvisionResult {
  final bool success;
  final ProvisionError? error;
  final String? agencyToken;
  final int? agencyId;
  final String? agencyCode;
  final String? agencyName;

  const ProvisionResult._({
    required this.success,
    this.error,
    this.agencyToken,
    this.agencyId,
    this.agencyCode,
    this.agencyName,
  });

  factory ProvisionResult.ok({
    required String agencyToken,
    int? agencyId,
    String? agencyCode,
    String? agencyName,
  }) => ProvisionResult._(
    success: true,
    agencyToken: agencyToken,
    agencyId: agencyId,
    agencyCode: agencyCode,
    agencyName: agencyName,
  );

  factory ProvisionResult.fail(ProvisionError error) =>
      ProvisionResult._(success: false, error: error);
}

class ProvisioningService {
  ProvisioningService._internal();
  static final ProvisioningService _instance = ProvisioningService._internal();
  factory ProvisioningService() => _instance;

  final ApiClient _api = ApiClient();
  final LocalStorageService _storage = LocalStorageService();

  // Extract payload string from a scanned deep link.
  // Accepts: modbusgo://provision?payload=XXXX  OR  https://.../provision?payload=XXXX
  String? extractPayload(String scannedValue) {
    try {
      final uri = Uri.parse(scannedValue.trim());
      final payload = uri.queryParameters['payload'];
      if (payload != null && payload.isNotEmpty) return payload;
      return null;
    } catch (_) {
      return null;
    }
  }

  // Map backend error code → enum.
  ProvisionError _mapError(String? code) {
    switch (code) {
      case 'DECRYPTION_FAILED':
        return ProvisionError.decryptionFailed;
      case 'PAYLOAD_EXPIRED':
        return ProvisionError.payloadExpired;
      case 'AGENCY_NOT_FOUND':
        return ProvisionError.agencyNotFound;
      case 'AGENCY_INACTIVE':
        return ProvisionError.agencyInactive;
      case 'TOKEN_EXPIRED':
        return ProvisionError.tokenExpired;
      case 'NONCE_MISMATCH':
        return ProvisionError.nonceMismatch;
      default:
        return ProvisionError.unknown;
    }
  }

  // Verify scanned QR + persist agency data on success.
  Future<ProvisionResult> provisionFromScan(String scannedValue) async {
    final payload = extractPayload(scannedValue);
    if (payload == null) {
      return ProvisionResult.fail(ProvisionError.invalidLink);
    }

    try {
      final res = await _api.dio.post(
        '/provision/verify',
        data: {'payload': payload},
      );

      final body = res.data;
      final ok = body is Map && body['success'] == true;

      if (res.statusCode == 200 && ok) {
        final token = body['agency_token'] as String?;
        if (token == null || token.isEmpty) {
          return ProvisionResult.fail(ProvisionError.unknown);
        }

        final agencyId = body['agency_id'] is int
            ? body['agency_id'] as int
            : null;
        final agencyCode = body['agency_code'] as String?;
        final agencyName = body['agency_name'] as String?;

        // Clean slate then persist (re-provision safe).
        await _storage.clearAllData();
        await _storage.saveAgencyToken(token);
        if (agencyId != null) await _storage.saveAgencyId(agencyId);
        await _storage.saveAgencyInfo(code: agencyCode, name: agencyName);

        return ProvisionResult.ok(
          agencyToken: token,
          agencyId: agencyId,
          agencyCode: agencyCode,
          agencyName: agencyName,
        );
      }

      final code = body is Map ? body['error'] as String? : null;
      return ProvisionResult.fail(_mapError(code));
    } on DioException catch (e) {
      if (kDebugMode) print('[Provisioning] DioException: ${e.message}');
      return ProvisionResult.fail(ProvisionError.network);
    } catch (e) {
      if (kDebugMode) print('[Provisioning] error: $e');
      return ProvisionResult.fail(ProvisionError.unknown);
    }
  }
}