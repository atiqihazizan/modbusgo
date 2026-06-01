import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import './widgets/qr_error_widget.dart';
import './widgets/qr_instruction_widget.dart';
import './widgets/qr_overlay_widget.dart';
import './widgets/qr_processing_widget.dart';

enum _ScanState { scanning, processing, error, success }

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace with [Riverpod/Bloc] for production
  _ScanState _scanState = _ScanState.scanning;
  String _errorMessage = '';

  late AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    super.dispose();
  }

  void _onMockScanSuccess() async {
    // TODO: connect real logic — handle QR scan result
    setState(() => _scanState = _ScanState.processing);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      // Mock: simulate successful provisioning
      setState(() => _scanState = _ScanState.success);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) context.go(AppRoutes.bootScreen);
    }
  }

  void _onMockScanError() {
    setState(() {
      _scanState = _ScanState.error;
      _errorMessage =
          'Invalid QR code format. Expected: modbusgo://provision?payload=...';
    });
  }

  void _onDismissError() {
    setState(() => _scanState = _ScanState.scanning);
  }

  void _onCancel() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final frameSize = isTablet ? 320.0 : size.width * 0.72;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera placeholder — TODO: connect mobile_scanner
          _CameraPlaceholder(),

          // QR overlay with scanning animation
          if (_scanState == _ScanState.scanning)
            QrOverlayWidget(
              frameSize: frameSize,
              scanLineController: _scanLineController,
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _GlassIconButton(iconName: 'arrow_back', onTap: _onCancel),
                  const Spacer(),
                  Text(
                    'Scan Provisioning QR',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _GlassIconButton(
                    iconName: 'flash_off',
                    onTap: () {
                      // TODO: connect real logic — toggle flashlight
                    },
                  ),
                ],
              ),
            ),
          ),

          // Instruction text
          if (_scanState == _ScanState.scanning)
            QrInstructionWidget(frameSize: frameSize),

          // Processing overlay
          if (_scanState == _ScanState.processing) const QrProcessingWidget(),

          // Success overlay
          if (_scanState == _ScanState.success) _SuccessOverlay(),

          // Error card
          if (_scanState == _ScanState.error)
            QrErrorWidget(message: _errorMessage, onDismiss: _onDismissError),

          // Bottom actions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Demo buttons
                    if (_scanState == _ScanState.scanning) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _GlassButton(
                              label: 'Simulate Success',
                              iconName: 'check_circle',
                              onTap: _onMockScanSuccess,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GlassButton(
                              label: 'Simulate Error',
                              iconName: 'error',
                              onTap: _onMockScanError,
                              color: AppTheme.errorColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    _GlassButton(
                      label: 'Cancel',
                      iconName: 'close',
                      onTap: _onCancel,
                      isFullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: connect real logic — replace with mobile_scanner MobileScanner widget
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomIconWidget(
              iconName: 'camera_alt',
              color: Colors.white.withAlpha(38),
              size: 80,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Preview',
              style: TextStyle(
                color: Colors.white.withAlpha(51),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '// TODO: connect mobile_scanner',
              style: TextStyle(
                color: Colors.white.withAlpha(26),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final String iconName;
  final VoidCallback onTap;

  const _GlassIconButton({required this.iconName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(51)),
        ),
        child: Center(
          child: CustomIconWidget(
            iconName: iconName,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final String iconName;
  final VoidCallback onTap;
  final Color? color;
  final bool isFullWidth;

  const _GlassButton({
    required this.label,
    required this.iconName,
    required this.onTap,
    this.color,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: c.withAlpha(31),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withAlpha(77)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            CustomIconWidget(iconName: iconName, color: c, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(179),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CustomIconWidget(
                  iconName: 'check',
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'QR Code Verified!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Redirecting…',
              style: TextStyle(
                color: Colors.white.withAlpha(179),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
