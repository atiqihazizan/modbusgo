import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class SplashLogoWidget extends StatefulWidget {
  final bool isLoading;

  const SplashLogoWidget({super.key, required this.isLoading});

  @override
  State<SplashLogoWidget> createState() => _SplashLogoWidgetState();
}

class _SplashLogoWidgetState extends State<SplashLogoWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(scale: _scaleAnim, child: child),
      ),
      child: Column(
        children: [
          // Transparent background — GO logo
          SizedBox(
            width: 200,
            height: 200,
            child: Image.asset(
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Center(
                child: CustomIconWidget(
                  iconName: 'memory',
                  color: AppTheme.primary,
                  size: 72,
                ),
              ),
              "assets/images/GO-1780372541638.png",
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(),
          const SizedBox(height: 6),
          Text(
            'Device Management & GPS Tracking',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
