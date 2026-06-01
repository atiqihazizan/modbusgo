import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/custom_icon_widget.dart';

class DeviceInfoCardWidget extends StatelessWidget {
  final String deviceId;
  final String agencyCode;
  final String coordinates;

  const DeviceInfoCardWidget({
    super.key,
    required this.deviceId,
    required this.agencyCode,
    required this.coordinates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: CustomIconWidget(
                iconName: 'memory',
                color: theme.colorScheme.primary,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceId,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  agencyCode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CustomIconWidget(
                iconName: 'location_on',
                color: theme.colorScheme.onSurfaceVariant,
                size: 14,
              ),
              const SizedBox(height: 2),
              Text(
                coordinates,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
