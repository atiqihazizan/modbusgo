import 'package:flutter/material.dart';

import '../core/app_export.dart';

enum BadgeStatus {
  online,
  offline,
  provisioned,
  notProvisioned,
  moving,
  idle,
  good,
  warning,
  error,
}

class StatusBadgeWidget extends StatefulWidget {
  final BadgeStatus status;
  final bool animate;
  final double? fontSize;

  const StatusBadgeWidget({
    super.key,
    required this.status,
    this.animate = false,
    this.fontSize,
  });

  @override
  State<StatusBadgeWidget> createState() => _StatusBadgeWidgetState();
}

class _StatusBadgeWidgetState extends State<StatusBadgeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.animate && widget.status == BadgeStatus.online) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  _BadgeConfig get _config {
    switch (widget.status) {
      case BadgeStatus.online:
        return _BadgeConfig(
          label: 'Online',
          icon: 'wifi',
          bg: AppTheme.successContainer,
          fg: AppTheme.success,
        );
      case BadgeStatus.offline:
        return _BadgeConfig(
          label: 'Offline',
          icon: 'wifi_off',
          bg: AppTheme.errorContainer,
          fg: AppTheme.errorColor,
        );
      case BadgeStatus.provisioned:
        return _BadgeConfig(
          label: 'Provisioned',
          icon: 'verified',
          bg: AppTheme.primaryContainer,
          fg: AppTheme.primary,
        );
      case BadgeStatus.notProvisioned:
        return _BadgeConfig(
          label: 'Not Provisioned',
          icon: 'error_outline',
          bg: AppTheme.warningContainer,
          fg: AppTheme.warning,
        );
      case BadgeStatus.moving:
        return _BadgeConfig(
          label: 'Moving',
          icon: 'directions_run',
          bg: AppTheme.primaryContainer,
          fg: AppTheme.primary,
        );
      case BadgeStatus.idle:
        return _BadgeConfig(
          label: 'Idle',
          icon: 'pause_circle_outline',
          bg: AppTheme.warningContainer,
          fg: AppTheme.warning,
        );
      case BadgeStatus.good:
        return _BadgeConfig(
          label: 'Good',
          icon: 'check_circle_outline',
          bg: AppTheme.successContainer,
          fg: AppTheme.success,
        );
      case BadgeStatus.warning:
        return _BadgeConfig(
          label: 'Warning',
          icon: 'warning_amber',
          bg: AppTheme.warningContainer,
          fg: AppTheme.warning,
        );
      case BadgeStatus.error:
        return _BadgeConfig(
          label: 'Error',
          icon: 'cancel',
          bg: AppTheme.errorContainer,
          fg: AppTheme.errorColor,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final fs = widget.fontSize ?? 12.0;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomIconWidget(
            iconName: config.icon,
            color: config.fg,
            size: fs + 2,
          ),
          const SizedBox(width: 5),
          Text(
            config.label,
            style: TextStyle(
              fontSize: fs,
              fontWeight: FontWeight.w600,
              color: config.fg,
            ),
          ),
        ],
      ),
    );

    if (widget.animate && widget.status == BadgeStatus.online) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) =>
            Transform.scale(scale: _pulseAnimation.value, child: child),
        child: badge,
      );
    }
    return badge;
  }
}

class _BadgeConfig {
  final String label;
  final String icon;
  final Color bg;
  final Color fg;
  const _BadgeConfig({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
}
