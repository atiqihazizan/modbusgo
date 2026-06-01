import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/custom_icon_widget.dart';

class AgencyHeaderBarWidget extends StatelessWidget {
  final String agencyName;
  final String agencyCode;
  final VoidCallback onRefreshGps;
  final VoidCallback onManualEmit;
  final bool isEmitting;

  const AgencyHeaderBarWidget({
    super.key,
    required this.agencyName,
    required this.agencyCode,
    required this.onRefreshGps,
    required this.onManualEmit,
    required this.isEmitting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: CustomIconWidget(
                iconName: 'business',
                color: theme.colorScheme.secondary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agencyName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  agencyCode,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _ActionIconButton(
            iconName: 'gps_fixed',
            tooltip: 'Refresh GPS',
            onTap: onRefreshGps,
            color: theme.colorScheme.secondary,
            bgColor: theme.colorScheme.secondaryContainer,
          ),
          const SizedBox(width: 6),
          _ActionIconButton(
            iconName: 'send',
            tooltip: 'Manual Emit',
            onTap: isEmitting ? null : onManualEmit,
            color: theme.colorScheme.primary,
            bgColor: theme.colorScheme.primaryContainer,
            isLoading: isEmitting,
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final String iconName;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final Color bgColor;
  final bool isLoading;

  const _ActionIconButton({
    required this.iconName,
    required this.tooltip,
    required this.onTap,
    required this.color,
    required this.bgColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : CustomIconWidget(iconName: iconName, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}
