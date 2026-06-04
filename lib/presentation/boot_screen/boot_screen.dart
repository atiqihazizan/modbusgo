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

class _BootScreenState extends State<BootScreen> {
  static const Duration _minBootVisible = Duration(milliseconds: 1400);

  late final DateTime _bootStartedAt;

  bool _isLoading = true;
  bool _offlineBlocked = false;
  String _statusMessage = 'Starting…';
  String _offlineDetail =
      'Internet connection is required to set up or restore this device.';

  @override
  void initState() {
    super.initState();
    _bootStartedAt = DateTime.now();
    _runBootSequence();
  }

  Future<void> _waitMinBootVisible() async {
    final elapsed = DateTime.now().difference(_bootStartedAt);
    final remaining = _minBootVisible - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _navigateAfterBoot(String route) async {
    await _waitMinBootVisible();
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _navigateRegistered(LocalStorageService storage) async {
    final needApproval = await storage.getNeedApproval();
    if (!mounted) return;
    await _navigateAfterBoot(
      needApproval ? AppRoutes.pendingScreen : AppRoutes.homeScreen,
    );
  }

  Future<void> _runBootSequence() async {
    setState(() {
      _isLoading = true;
      _offlineBlocked = false;
      _statusMessage = 'Starting…';
    });

    try {
      await DeviceIdentityService().getDeviceId();

      if (!mounted) return;
      setState(() => _statusMessage = 'Checking device registration…');

      final storage = LocalStorageService();
      final hasDevice = await storage.hasDeviceInfo();
      final hasToken = await storage.hasAgencyToken();

      if (hasDevice && hasToken) {
        await _navigateRegistered(storage);
        return;
      }

      setState(() => _statusMessage = 'Restoring device data…');
      final restore = await RegistrationService().bootRestoreFromBackend();

      if (!mounted) return;

      switch (restore) {
        case BootRestoreResult.success:
          await _navigateRegistered(storage);
        case BootRestoreResult.notRegistered:
          await _navigateAfterBoot(AppRoutes.provisionScreen);
        case BootRestoreResult.offline:
        case BootRestoreResult.networkError:
          setState(() {
            _isLoading = false;
            _offlineBlocked = true;
            _statusMessage = 'No internet connection';
            _offlineDetail = restore == BootRestoreResult.offline
                ? 'Connect to Wi‑Fi or mobile data, then tap Retry.'
                : 'Could not reach the server. Check your connection and tap Retry.';
          });
      }
    } catch (_) {
      if (!mounted) return;
      final online = await RegistrationService().hasInternetConnection();
      if (!online) {
        setState(() {
          _isLoading = false;
          _offlineBlocked = true;
          _statusMessage = 'No internet connection';
          _offlineDetail =
              'Connect to Wi‑Fi or mobile data, then tap Retry.';
        });
        return;
      }
      final storage = LocalStorageService();
      final hasDevice = await storage.hasDeviceInfo();
      final hasToken = await storage.hasAgencyToken();
      if (hasDevice && hasToken) {
        await _navigateRegistered(storage);
      } else {
        await _navigateAfterBoot(AppRoutes.provisionScreen);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
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
                      if (_offlineBlocked)
                        _OfflineBlockedWidget(
                          title: _statusMessage,
                          detail: _offlineDetail,
                          onRetry: _runBootSequence,
                        )
                      else
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
    );
  }
}

class _OfflineBlockedWidget extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onRetry;

  const _OfflineBlockedWidget({
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: theme.colorScheme.error.withValues(alpha: 0.85),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('Retry'),
        ),
      ],
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
