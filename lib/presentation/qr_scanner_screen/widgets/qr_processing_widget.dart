import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class QrProcessingWidget extends StatelessWidget {
  const QrProcessingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(179),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(102),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Processing provisioning…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Verifying device credentials',
                style: TextStyle(
                  color: Colors.white.withAlpha(153),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
