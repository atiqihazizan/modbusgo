import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../custom_icon_widget.dart';

class InfoRow extends StatelessWidget {
  final String iconName;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  const InfoRow({
    super.key,
    required this.iconName,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              CustomIconWidget(
                iconName: iconName,
                color: theme.colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: valueColor ?? theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
