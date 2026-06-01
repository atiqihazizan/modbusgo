import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../custom_icon_widget.dart';

class PrimaryButton extends StatefulWidget {
  final String label;
  final String? iconName;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const PrimaryButton({
    super.key,
    required this.label,
    this.iconName,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.backgroundColor ?? theme.colorScheme.primary;
    final fg = widget.foregroundColor ?? Colors.white;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _scaleController.forward(),
        onTapUp: (_) => _scaleController.reverse(),
        onTapCancel: () => _scaleController.reverse(),
        child: SizedBox(
          width: widget.isFullWidth ? double.infinity : null,
          child: ElevatedButton(
            onPressed: widget.isLoading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              disabledBackgroundColor: bg.withAlpha(153),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.isLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    )
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.iconName != null) ...[
                          CustomIconWidget(
                            iconName: widget.iconName!,
                            color: fg,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
