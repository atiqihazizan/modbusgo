import 'package:flutter/material.dart';

import '../../core/app_export.dart';
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
        return 'Kod QR tidak sah.';
      case ProvisionError.network:
        return 'Tiada sambungan internet. Cuba lagi.';
      case ProvisionError.decryptionFailed:
        return 'Kod QR rosak atau tidak sah.';
      case ProvisionError.payloadExpired:
        return 'Kod QR telah tamat tempoh. Minta kod baru.';
      case ProvisionError.agencyNotFound:
        return 'Agensi tidak dijumpai.';
      case ProvisionError.agencyInactive:
        return 'Agensi tidak aktif.';
      case ProvisionError.tokenExpired:
        return 'Token agensi telah tamat tempoh. Minta kod baru.';
      case ProvisionError.nonceMismatch:
        return 'Kod QR tidak padan. Minta kod baru.';
      case ProvisionError.unknown:
        return 'Ralat tidak dijangka. Cuba lagi.';
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

    final regResult = await RegistrationService().registerDevice(
      name: deviceName.trim(),
    );
    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (regResult.success) {
      if (regResult.needApproval) {
        context.go(AppRoutes.pendingScreen);
      } else {
        context.go(AppRoutes.homeScreen);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pendaftaran peranti gagal. Cuba lagi.')),
      );
    }
  }

  Future<String?> _showDeviceNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Nama Peranti'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Masukkan nama peranti'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Simpan'),
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
                  'Peruntukan Peranti',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Imbas kod QR peruntukan daripada pentadbir anda untuk mendaftarkan peranti ini.',
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
                            'Memproses…',
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
                          label: const Text('Imbas QR'),
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
