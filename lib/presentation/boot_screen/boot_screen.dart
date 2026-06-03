import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/registration_service.dart';
import './widgets/splash_logo_widget.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  final bool _isLoading = true;
  String _statusMessage = 'Starting…';

  late AnimationController _bgController;
  late Animation<double> _bgAnimation;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _bgAnimation = CurvedAnimation(
      parent: _bgController,
      curve: Curves.easeOutCubic,
    );
    _runBootSequence();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _runBootSequence() async {
    try {
      await DeviceIdentityService().getDeviceId();
      
      if (!mounted) return;
      setState(() => _statusMessage = 'Checking device registration…');

      final storage = LocalStorageService();
      final hasDevice = await storage.hasDeviceInfo();
      final hasToken = await storage.hasAgencyToken();

      if (hasDevice && hasToken) {
        final needApproval = await storage.getNeedApproval();
        if (!mounted) return;
        context.go(
          needApproval ? AppRoutes.pendingScreen : AppRoutes.homeScreen,
        );
        return;
      }

      setState(() => _statusMessage = 'Restoring device data…');
      final restored = await RegistrationService().restoreFromBackend();

      if (!mounted) return;
      if (restored) {
        final needApproval = await storage.getNeedApproval();
        if (!mounted) return;
        context.go(
          needApproval ? AppRoutes.pendingScreen : AppRoutes.homeScreen,
        );
      } else {
        context.go(AppRoutes.provisionScreen);
      }
    } catch (_) {
      if (mounted) context.go(AppRoutes.provisionScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _bgAnimation,
          builder: (context, child) =>
              Opacity(opacity: _bgAnimation.value, child: child),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withAlpha(20),
                  theme.colorScheme.surface,
                  theme.colorScheme.secondaryContainer.withAlpha(38),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width > 600 ? 480 : double.infinity,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),
                        SplashLogoWidget(isLoading: _isLoading),
                        const SizedBox(height: 32),
                        _StatusMessageWidget(
                          message: _statusMessage,
                          isLoading: _isLoading,
                        ),
                        const Spacer(flex: 3),
                        Text(
                          'ModbusGo v1.0.0',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMessageWidget extends StatelessWidget {
  final String message;
  final bool isLoading;

  const _StatusMessageWidget({required this.message, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            message,
            key: ValueKey(message),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
