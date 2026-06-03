import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/services/provisioning_service.dart';
import '../../core/services/registration_service.dart';

class ProvisionScreen extends StatefulWidget {
  const ProvisionScreen({super.key});

  @override
  State<ProvisionScreen> createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  bool _isProcessing = false;

  String _mapProvisionError(ProvisionError error) {
    switch (error) {
      case ProvisionError.invalidLink:
        return 'Invalid QR code.';
      case ProvisionError.network:
        return 'No internet connection. Please try again.';
      case ProvisionError.decryptionFailed:
        return 'QR code is corrupted or invalid.';
      case ProvisionError.payloadExpired:
        return 'QR code has expired. Request a new one.';
      case ProvisionError.agencyNotFound:
        return 'Agency not found.';
      case ProvisionError.agencyInactive:
        return 'Agency is inactive.';
      case ProvisionError.tokenExpired:
        return 'Agency token has expired. Request a new code.';
      case ProvisionError.nonceMismatch:
        return 'QR code mismatch. Request a new code.';
      case ProvisionError.unknown:
        return 'Unexpected error. Please try again.';
    }
  }

  Future<void> _onScanPressed() async {
    final scanned = await context.push<String>(AppRoutes.scannerScreen);
    if (scanned == null || scanned.isEmpty) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);

    final result = await ProvisioningService().provisionFromScan(scanned);

    if (!mounted) return;

    if (!result.success) {
      setState(() => _isProcessing = false);
      final msg = _mapProvisionError(result.error ?? ProvisionError.unknown);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final deviceName = await _showDeviceNameDialog();
    if (!mounted) return;

    if (deviceName == null || deviceName.trim().isEmpty) {
      setState(() => _isProcessing = false);
      return;
    }

    // WAJIB: dapatkan GPS fix sebelum daftar. Gagal = batal provisioning.
    final fix = await LocationService().getCurrentFix();
    if (fix == null) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS unavailable. Provisioning cancelled. '
            'Enable GPS and allow location access, then try again.',
          ),
        ),
      );
      return;
    }

    final regResult = await RegistrationService().registerDevice(
      name: deviceName.trim(),
    );
    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (regResult.success) {
      await _emitInitialLocation(fix);
      if (regResult.needApproval) {
        context.go(AppRoutes.pendingScreen);
      } else {
        context.go(AppRoutes.homeScreen);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device registration failed. Please try again.'),
        ),
      );
    }
  }

  /// Send one real lat/lon bundle after successful provisioning.
  Future<void> _emitInitialLocation(LocationFix fix) async {
    try {
      final mqtt = MqttService();
      if (!mqtt.isConnected) {
        final deviceId = await DeviceIdentityService().getDeviceId();
        if (deviceId.isEmpty) return;
        await mqtt.init(deviceId: deviceId);
        await Future.delayed(const Duration(seconds: 2));
      }
      mqtt.publishBundle({
        'data_type': 'MG',
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'speed': fix.speed,
        if (fix.heading != null) 'heading': fix.heading,
        'sensor_data': [-1],
      });
    } catch (_) {
      // Silent — do not block flow.
    }
  }

  Future<String?> _showDeviceNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Device Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter device name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Image.asset(
                  width: 100,
                  height: 100,
                  "assets/images/app_logo.png",
                ),
                const SizedBox(height: 24),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CustomIconWidget(
                      iconName: 'qr_code_scanner',
                      color: theme.colorScheme.primary,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Device Provisioning',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan the provisioning QR code from your administrator to register this device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 2),
                _isProcessing
                    ? Column(
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Processing…',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _onScanPressed,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan QR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
