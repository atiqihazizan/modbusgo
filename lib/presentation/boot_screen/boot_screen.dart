import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import './widgets/boot_action_widget.dart';
import './widgets/provisioning_status_widget.dart';
import './widgets/splash_logo_widget.dart';

// Mock device state — TODO: connect real logic
class _MockDeviceState {
  static bool isProvisioned = false;
  static bool isOnline = false;
  static String deviceName = '';
  static String statusMessage = 'Initializing…';
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace with [Riverpod/Bloc] for production
  bool _isLoading = true;
  bool _isProvisioned = false;
  bool _isOnline = false;
  String _statusMessage = 'Initializing…';
  bool _showAction = false;

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
    // TODO: connect real logic — check SharedPreferences for provisioning state
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _statusMessage = 'Checking device registration…');

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Mock: simulate not provisioned
    final provisioned = _MockDeviceState.isProvisioned;
    final online = _MockDeviceState.isOnline;

    setState(() {
      _isLoading = false;
      _isProvisioned = provisioned;
      _isOnline = online;
      _statusMessage = provisioned
          ? (online ? 'Device ready' : 'Device offline — connecting…')
          : 'Device not registered';
      _showAction = true;
    });

    if (provisioned) {
      // TODO: connect real logic — navigate to home after verifying registration
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) context.go(AppRoutes.homeScreen);
    }
  }

  void _onScanQr() {
    context.push(AppRoutes.qrScannerScreen);
  }

  void _onDemoGoHome() {
    // Demo shortcut — TODO: remove in production
    context.go(AppRoutes.homeScreen);
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
                        const Spacer(flex: 2),
                        AnimatedOpacity(
                          opacity: _showAction ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: AnimatedSlide(
                            offset: _showAction
                                ? Offset.zero
                                : const Offset(0, 0.3),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            child: BootActionWidget(
                              isProvisioned: _isProvisioned,
                              onScanQr: _onScanQr,
                              onDemoGoHome: _onDemoGoHome,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ProvisioningStatusWidget(
                          isProvisioned: _isProvisioned,
                          isOnline: _isOnline,
                        ),
                        const SizedBox(height: 24),
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
        if (isLoading) ...[
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
      ],
    );
  }
}
