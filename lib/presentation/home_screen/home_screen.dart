import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/mqtt_service.dart';
import './widgets/home_action_bar_widget.dart';
import './widgets/modbus_device_panel_widget.dart';
import './widgets/unified_dashboard_card_widget.dart';

// Mock data — TODO: Replace with [Riverpod/Bloc] for production
// class _MockHomeState {
//   static const String deviceName = 'RTU-UNIT-04';
//   static const String deviceId = 'MBG-2024-0047';
//   static const String agencyName = 'Jabatan Pengairan Selangor';
//   static const String agencyCode = 'JPS-SEL';
//   static bool isOnline = true;
//   static bool isMoving = false;
//   static String lastEmit = '2 min ago';
//   static String lastCoordinates = '3.1390° N, 101.6869° E';
// }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Data sebenar dari storage
  String _deviceName = '-';
  String _deviceId = '—';
  String _agencyName = '—';
  String _agencyCode = '—';

  // Status hidup
  bool _isOnline = false;
  bool _isMoving = false;
  String _lastEmit = 'Not sent yet';
  String _coordinates = '—';

  bool _isRefreshing = false;
  bool _isEmitting = false;

  StreamSubscription<LocationFix>? _locSub;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _startLocation();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    final storage = LocalStorageService();
    final info = await storage.getDeviceInfo();
    final agencyName = await storage.getAgencyName();
    final agencyCode = await storage.getAgencyCode();
    if (!mounted) return;
    setState(() {
      _deviceName = (info?['name']?.isNotEmpty == true) ? info!['name']! : '—';
      _deviceId = (info?['device_id']?.isNotEmpty == true)
          ? info!['device_id']!
          : '—';
      _agencyName = (agencyName != null && agencyName.isNotEmpty)
          ? agencyName
          : '—';
      _agencyCode = (agencyCode != null && agencyCode.isNotEmpty)
          ? agencyCode
          : '—';
    });
  }

  Future<void> _startLocation() async {
    // Start GPS in background — does not block UI.
    await LocationService().start();

    // Listen for incoming fixes → update coordinates + motion status.
    _locSub = LocationService().stream.listen((fix) {
      if (!mounted) return;
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed > 0.5; // motion threshold (m/s)
      });
    });

    // Show initial fix if already available.
    final f = LocationService().lastFix;
    if (f != null && mounted) {
      setState(() => _coordinates = _fmtCoords(f.latitude, f.longitude));
    }
  }

  String _fmtCoords(double lat, double lon) {
    return '${lat.abs().toStringAsFixed(4)}, ${lon.abs().toStringAsFixed(4)}';
    // final latDir = lat >= 0 ? 'N' : 'S';
    // final lonDir = lon >= 0 ? 'E' : 'W';
    // return '${lat.abs().toStringAsFixed(4)}° $latDir, '
    //     '${lon.abs().toStringAsFixed(4)}° $lonDir';
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadDeviceInfo();
    final fix = await LocationService().getCurrentFix();
    if (mounted && fix != null) {
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed > 0.5;
      });
    }
    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Status updated'),
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

    // Ensure connected (init once — use real device_id).
    if (!mqtt.isConnected) {
      final deviceId = await DeviceIdentityService().getDeviceId();
      if (deviceId.isEmpty) {
        if (mounted) {
          setState(() => _isEmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device ID missing — provision first'),
            ),
          );
        }
        return;
      }
      await mqtt.init(deviceId: deviceId);
      await Future.delayed(const Duration(seconds: 2)); // allow time to connect
    }

    // Use real GPS fix if available.
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
      final last = LocationService().lastFix;
      setState(() {
        _isEmitting = false;
        _isOnline = mqtt.isConnected;
        _lastEmit = 'Just now';
        if (last != null) {
          _coordinates = _fmtCoords(last.latitude, last.longitude);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mqtt.isConnected ? 'Tracking data sent' : 'Offline — data queued',
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
    final fix = await LocationService().getCurrentFix();
    if (!mounted) return;
    if (fix != null) {
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed > 0.5;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('GPS updated'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS unavailable. Enable GPS and allow location.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
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
            // SizedBox(width: 36, height: 36, child: SizedBox()),
            // const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _deviceName.toUpperCase(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _deviceId,
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
                  UnifiedDashboardCardWidget(
                    deviceId: _deviceId,
                    agencyCode: _agencyCode.toUpperCase(),
                    coordinates: _coordinates,
                    agencyName: _agencyName.toUpperCase(),
                    onRefreshGps: _onRefreshGps,
                    onManualEmit: _onManualEmit,
                    isEmitting: _isEmitting,
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
