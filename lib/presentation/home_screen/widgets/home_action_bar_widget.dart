import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/custom_icon_widget.dart';

class HomeActionBarWidget extends StatelessWidget {
  final bool isEmitting;
  final VoidCallback onManualEmit;
  final VoidCallback onViewLogs;

  const HomeActionBarWidget({
    super.key,
    required this.isEmitting,
    required this.onManualEmit,
    required this.onViewLogs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: PrimaryButton(
                label: 'Emit Tracking Data',
                iconName: 'send',
                onPressed: onManualEmit,
                isLoading: isEmitting,
                isFullWidth: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: onViewLogs,
                icon: CustomIconWidget(
                  iconName: 'list_alt',
                  color: theme.colorScheme.primary,
                  size: 16,
                ),
                label: const Text('View Logs'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
