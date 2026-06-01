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
            width: 160,
            height: 160,
            child: Image.asset(
              'assets/images/GO-1780310152509.png',
              fit: BoxFit.contain,
              semanticLabel: 'ModbusGo splash logo',
              errorBuilder: (context, error, stackTrace) => Center(
                child: CustomIconWidget(
                  iconName: 'memory',
                  color: AppTheme.primary,
                  size: 72,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'ModbusGo',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
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
