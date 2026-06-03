import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/services/publish_service.dart';
import '../../core/services/registration_service.dart';
import './widgets/modbus_device_panel_widget.dart';
import './widgets/unified_dashboard_card_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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

  // Auto-publish throttle — elak spam bila GPS hantar fix laju.
  DateTime _lastAutoPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _autoPublishMinGap = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDeviceInfo();
    _startLocation();
    _startMqtt(); // MQTT keep-online sejurus masuk home
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locSub?.cancel();
    final mqtt = MqttService();
    mqtt.onConnectionChanged = null;
    mqtt.onReconnectExhausted = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MqttService().resumeReconnect();
    }
  }

  Future<void> _loadDeviceInfo() async {
    final storage = LocalStorageService();

    // Sync terkini dari backend dulu — pastikan agency_code/name tak hilang.
    // Senyap; kalau gagal (offline), guna nilai storage sedia ada.
    try {
      await RegistrationService().restoreFromBackend();
    } catch (_) {}

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

  Future<void> _startMqtt() async {
    final mqtt = MqttService();

    mqtt.onConnectionChanged = (connected) {
      if (!mounted) return;
      setState(() => _isOnline = connected);
    };
    mqtt.onReconnectExhausted = () {
      if (!mounted) return;
      setState(() => _isOnline = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'MQTT gagal sambung selepas 5 percubaan. '
            'Sila reconnect manual di skrin Profile.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'PROFILE',
            textColor: Colors.white,
            onPressed: () => context.push(AppRoutes.profileScreen),
          ),
        ),
      );
    };

    final deviceId = await DeviceIdentityService().getDeviceId();
    if (deviceId.isEmpty) return;
    await mqtt.init(deviceId: deviceId);

    if (mounted) setState(() => _isOnline = mqtt.isConnected);
  }

  Future<void> _startLocation() async {
    await LocationService().start();

    // Listen for incoming fixes → update UI + auto-publish.
    _locSub = LocationService().stream.listen((fix) {
      if (!mounted) return;
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed > 0.5;
      });
      // SEBELUM: _autoPublish(fix);
      PublishService().publishGps(fix); // pintu tunggal + hormati pause
    });

    // Show initial fix if already available.
    final f = LocationService().lastFix;
    if (f != null && mounted) {
      setState(() => _coordinates = _fmtCoords(f.latitude, f.longitude));
    }
  }

  /// Auto-publish bila lokasi berubah. Throttle ringan elak spam.
  /// Sensor data tiada → guna placeholder [-1] (sama macam manual emit).
  void _autoPublish(LocationFix fix) {
    final now = DateTime.now();
    if (now.difference(_lastAutoPublish) < _autoPublishMinGap) return;
    _lastAutoPublish = now;

    final mqtt = MqttService();
    mqtt.publishBundle({
      'data_type': 'MG',
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'speed': fix.speed,
      if (fix.heading != null) 'heading': fix.heading,
      'sensor_data': [-1],
    });

    if (mounted) {
      setState(() {
        _isOnline = mqtt.isConnected;
        _lastEmit = mqtt.isConnected ? 'Auto · just now' : 'Queued (offline)';
      });
    }
  }

  String _fmtCoords(double lat, double lon) {
    return '${lat.abs().toStringAsFixed(4)}, ${lon.abs().toStringAsFixed(4)}';
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
      setState(() {
        _isRefreshing = false;
        _isOnline = MqttService().isConnected;
      });
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
      await Future.delayed(const Duration(seconds: 2));
    }

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
      // Refresh manual juga publish satu fix segar.
      _lastAutoPublish = DateTime.fromMillisecondsSinceEpoch(0);
      _autoPublish(fix);
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
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.profileScreen),
            icon: CustomIconWidget(
              iconName: 'account_circle',
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            tooltip: 'Profile',
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
                  const ModbusDevicePanelWidget(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
