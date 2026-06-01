import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';

class MqttDiagnosticsWidget extends StatelessWidget {
  final String mqttHealth;
  final String mqttBroker;
  final String lastEmit;
  final String emitInterval;
  final bool isExpanded;
  final VoidCallback onToggle;

  const MqttDiagnosticsWidget({
    super.key,
    required this.mqttHealth,
    required this.mqttBroker,
    required this.lastEmit,
    required this.emitInterval,
    required this.isExpanded,
    required this.onToggle,
  });

  Color get _healthColor => AppTheme.mqttHealthColor(mqttHealth);
  String get _healthLabel {
    switch (mqttHealth) {
      case 'good':
        return 'Connected';
      case 'idle':
        return 'Idle';
      default:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _healthColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _healthColor.withAlpha(102),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MQTT Diagnostics',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_healthLabel · Last emit: $lastEmit',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: CustomIconWidget(
                      iconName: 'keyboard_arrow_down',
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: isExpanded
                ? Column(
                    children: [
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _DiagRow(
                              icon: 'router',
                              label: 'Broker',
                              value: mqttBroker,
                              valueColor: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 10),
                            _DiagRow(
                              icon: 'health_and_safety',
                              label: 'Connection Health',
                              value: _healthLabel,
                              valueColor: _healthColor,
                            ),
                            const SizedBox(height: 10),
                            _DiagRow(
                              icon: 'schedule',
                              label: 'Emit Interval',
                              value: emitInterval,
                            ),
                            const SizedBox(height: 10),
                            _DiagRow(
                              icon: 'send',
                              label: 'Last Emit',
                              value: lastEmit,
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  const _DiagRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CustomIconWidget(
          iconName: icon,
          color: theme.colorScheme.onSurfaceVariant,
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
