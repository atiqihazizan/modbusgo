import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/status_badge_widget.dart';

class TrackingStatusBarWidget extends StatelessWidget {
  final bool isOnline;
  final bool isMoving;
  final String lastEmit;

  const TrackingStatusBarWidget({
    super.key,
    required this.isOnline,
    required this.isMoving,
    required this.lastEmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: 'radar',
                color: theme.colorScheme.onSurfaceVariant,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                'Tracking Status',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Last emit: $lastEmit',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatusTile(
                  label: 'Connection',
                  badge: StatusBadgeWidget(
                    status: isOnline ? BadgeStatus.online : BadgeStatus.offline,
                    animate: isOnline,
                  ),
                  indicatorColor: isOnline
                      ? AppTheme.success
                      : AppTheme.errorColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusTile(
                  label: 'Motion',
                  badge: StatusBadgeWidget(
                    status: isMoving ? BadgeStatus.moving : BadgeStatus.idle,
                  ),
                  indicatorColor: isMoving
                      ? AppTheme.primary
                      : AppTheme.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final Widget badge;
  final Color indicatorColor;

  const _StatusTile({
    required this.label,
    required this.badge,
    required this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          badge,
        ],
      ),
    );
  }
}
