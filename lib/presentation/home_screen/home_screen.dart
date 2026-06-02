import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/mqtt_service.dart';
import './widgets/agency_header_bar_widget.dart';
import './widgets/device_info_card_widget.dart';
import './widgets/home_action_bar_widget.dart';
import './widgets/modbus_device_panel_widget.dart';
import './widgets/tracking_status_bar_widget.dart';

// Mock data — TODO: Replace with [Riverpod/Bloc] for production
class _MockHomeState {
  static const String deviceName = 'RTU-UNIT-04';
  static const String deviceId = 'MBG-2024-0047';
  static const String agencyName = 'Jabatan Pengairan Selangor';
  static const String agencyCode = 'JPS-SEL';
  static bool isOnline = true;
  static bool isMoving = false;
  static String lastEmit = '2 min ago';
  static String lastCoordinates = '3.1390° N, 101.6869° E';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final bool _isOnline = _MockHomeState.isOnline;
  final bool _isMoving = _MockHomeState.isMoving;
  String _lastEmit = _MockHomeState.lastEmit;
  bool _isRefreshing = false;
  bool _isEmitting = false;

  @override
  void initState() {
    super.initState();
    // Mula GPS di latar — tak block UI. Fix akan masuk bila sedia.
    LocationService().start();
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    // TODO: connect real logic — refresh GPS and device status
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _lastEmit = 'Just now';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Status refreshed'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onManualEmit() async {
    setState(() => _isEmitting = true);

    final mqtt = MqttService();

    // Pastikan connected (init sekali — guna device_id sebenar).
    if (!mqtt.isConnected) {
      final deviceId = await DeviceIdentityService().getDeviceId();
      if (deviceId.isEmpty) {
        if (mounted) {
          setState(() => _isEmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device ID tiada — provision dulu')),
          );
        }
        return;
      }
      await mqtt.init(deviceId: deviceId);
      await Future.delayed(const Duration(seconds: 2)); // beri masa connect
    }

    // Guna fix GPS sebenar kalau ada; kalau belum sedia, guna last/abai.
    final fix = LocationService().lastFix;
    mqtt.publishBundle({
      'data_type': 'MG',
      'latitude': fix?.latitude ?? 3.1390,
      'longitude': fix?.longitude ?? 101.6869,
      'speed': fix?.speed ?? 0,
      if (fix?.heading != null) 'heading': fix!.heading,
      'sensor_data': [-1],
    });

    if (mounted) {
      setState(() {
        _isEmitting = false;
        _lastEmit = 'Just now';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mqtt.isConnected
                ? 'Tracking data emitted'
                : 'Offline — data queued',
          ),
          backgroundColor: mqtt.isConnected ? AppTheme.success : Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onRefreshGps() async {
    // TODO: connect real logic — refresh GPS coordinates
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('GPS refreshed'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        title: Row(
          children: [
            // GO logo — transparent background
            SizedBox(
              width: 36,
              height: 36,
              child: Image.asset(
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: CustomIconWidget(
                    iconName: 'memory',
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                "assets/images/app_icon-1780309918034-removebg-preview-1780371862334.png",
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _MockHomeState.deviceName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _MockHomeState.deviceId,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.qrScannerScreen),
            icon: CustomIconWidget(
              iconName: 'qr_code_scanner',
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            tooltip: 'Scan QR',
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.settingsScreen),
            icon: CustomIconWidget(
              iconName: 'settings',
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: theme.colorScheme.primary,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isTablet ? 640 : double.infinity,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  DeviceInfoCardWidget(
                    deviceId: _MockHomeState.deviceId,
                    agencyCode: _MockHomeState.agencyCode,
                    coordinates: _MockHomeState.lastCoordinates,
                  ),
                  const SizedBox(height: 12),
                  AgencyHeaderBarWidget(
                    agencyName: _MockHomeState.agencyName,
                    agencyCode: _MockHomeState.agencyCode,
                    onRefreshGps: _onRefreshGps,
                    onManualEmit: _onManualEmit,
                    isEmitting: _isEmitting,
                  ),
                  const SizedBox(height: 12),
                  TrackingStatusBarWidget(
                    isOnline: _isOnline,
                    isMoving: _isMoving,
                    lastEmit: _lastEmit,
                  ),
                  const SizedBox(height: 12),
                  // Modbus Device Panel — shows connected devices with WiFi/BT type and live values
                  const ModbusDevicePanelWidget(),
                  const SizedBox(height: 12),
                  // Modbus Settings — configure slave ID, address, length, type, etc.
                  const SizedBox(height: 20),
                  HomeActionBarWidget(
                    isEmitting: _isEmitting,
                    onManualEmit: _onManualEmit,
                    onViewLogs: () {
                      // TODO: connect real logic — navigate to TrackingLogsScreen
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs screen — coming soon'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
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
