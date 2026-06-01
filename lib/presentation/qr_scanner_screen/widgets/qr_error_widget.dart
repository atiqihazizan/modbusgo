import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class QrErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const QrErrorWidget({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 140,
      child: AnimatedSlide(
        offset: Offset.zero,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.errorColor.withAlpha(102)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.errorColor.withAlpha(51),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CustomIconWidget(
                iconName: 'error',
                color: AppTheme.errorColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Failed',
                      style: TextStyle(
                        color: AppTheme.errorColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        color: AppTheme.errorColor.withAlpha(204),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: CustomIconWidget(
                    iconName: 'close',
                    color: AppTheme.errorColor,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
