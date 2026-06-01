import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/custom_icon_widget.dart';

class BootActionWidget extends StatelessWidget {
  final bool isProvisioned;
  final VoidCallback onScanQr;
  final VoidCallback onDemoGoHome;

  const BootActionWidget({
    super.key,
    required this.isProvisioned,
    required this.onScanQr,
    required this.onDemoGoHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isProvisioned) return const SizedBox.shrink();

    return Column(
      children: [
        PrimaryButton(
          label: 'Scan QR Code',
          iconName: 'qr_code_scanner',
          onPressed: onScanQr,
          isFullWidth: true,
        ),
        const SizedBox(height: 12),
        // Demo shortcut — TODO: remove in production
        OutlinedButton.icon(
          onPressed: onDemoGoHome,
          icon: CustomIconWidget(
            iconName: 'arrow_forward',
            color: theme.colorScheme.primary,
            size: 16,
          ),
          label: const Text('Demo: Go to Home'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Scan a provisioning QR code to register your device',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
