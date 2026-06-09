import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/constants/tracking_publish_config.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDeviceInfo();
    unawaited(_bootstrapHome());
  }

  Future<void> _bootstrapHome() async {
    await _startLocation();
    await _startMqtt();
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
      PublishService().startScheduler();
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
      if (connected) {
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          _isOnline = true;
          _lastEmit = 'Just now';
        });
        return;
      }
      setState(() => _isOnline = false);
    };
    mqtt.onReconnectExhausted = () {
      if (!mounted) return;
      setState(() => _isOnline = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'MQTT failed to connect after 5 attempts. '
            'Will retry when the app returns to the foreground.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: 'Close',
            textColor: Colors.white,
            onPressed: () {
              messenger.hideCurrentSnackBar();
            },
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
    PublishService().startScheduler();

    // UI sahaja — publish GPS via PublishService.onLocationEvent (stream dalaman).
    _locSub = LocationService().stream.listen((fix) {
      if (!mounted) return;
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed >
            TrackingPublishConfig.motionMovingSpeedThresholdMps;
      });
    });

    // Show initial fix if already available.
    final f = LocationService().lastFix;
    if (f != null && mounted) {
      setState(() => _coordinates = _fmtCoords(f.latitude, f.longitude));
    }
  }

  String _fmtCoords(double lat, double lon) {
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadDeviceInfo();
    final fix = await LocationService().getCurrentFix();
    if (mounted && fix != null) {
      setState(() {
        _coordinates = _fmtCoords(fix.latitude, fix.longitude);
        _isMoving = fix.speed >
            TrackingPublishConfig.motionMovingSpeedThresholdMps;
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

    var fix = LocationService().lastFix;
    if (fix == null ||
        (fix.accuracy != null &&
            fix.accuracy! >
                TrackingPublishConfig.maxAcceptableAccuracyMeters)) {
      fix = await LocationService().getCurrentFix();
    }
    if (fix == null) {
      if (mounted) {
        setState(() => _isEmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS is not available. Turn on GPS and allow precise location.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await PublishService().publishManual(fix: fix);

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
        _isMoving = fix.speed >
            TrackingPublishConfig.motionMovingSpeedThresholdMps;
      });
      await PublishService().publishCurrentSnapshot(fix: fix);
      if (!mounted) return;
      setState(() {
        _lastEmit = MqttService().isConnected
            ? 'Just now'
            : 'Queued (offline)';
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
        title: Text(
          _agencyName.toUpperCase(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            // fontSize: 16,
            letterSpacing: 0.3,
            color: theme.colorScheme.onSurface,
          ),
        ),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
