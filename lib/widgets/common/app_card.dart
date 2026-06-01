import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double borderRadius;
  final VoidCallback? onTap;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius = 16,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        splashColor: theme.colorScheme.primary.withAlpha(20),
        highlightColor: theme.colorScheme.primary.withAlpha(10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border:
                border ??
                Border.all(color: theme.colorScheme.outline.withAlpha(128)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
