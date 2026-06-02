import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/services/registration_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Data ──
  String _deviceName = '';
  String _deviceId = '';
  String _agencyName = '';
  String _agencyCode = '';
  String _agencyToken = '';
  bool _isOnline = false;
  bool _isLoading = true;

  // ── Agency list / switch ──
  List<AgencyOption> _agencies = [];
  AgencyOption? _selectedAgency;
  bool _isSwitching = false;

  // ── Reconnect ──
  bool _isReconnecting = false;

  // ── Timer for live MQTT status ──
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    // Refresh MQTT status every 2 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() => _isOnline = MqttService().isConnected);
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final storage = LocalStorageService();
    final deviceInfo = await storage.getDeviceInfo();
    final agencyName = await storage.getAgencyName();
    final agencyCode = await storage.getAgencyCode();
    final agencyToken = await storage.getAgencyToken();
    final deviceId = await DeviceIdentityService().getDeviceId();
    final agencies = await RegistrationService().listAgencies();

    if (mounted) {
      setState(() {
        _deviceName = deviceInfo?['name'] ?? 'Unknown Device';
        _deviceId = deviceInfo?['device_id'] ?? deviceId;
        _agencyName = agencyName ?? '-';
        _agencyCode = agencyCode ?? '-';
        _agencyToken = agencyToken ?? '';
        _isOnline = MqttService().isConnected;
        _agencies = agencies;
        _isLoading = false;
      });
    }
  }

  String _maskToken(String token) {
    if (token.isEmpty) return '-';
    if (token.length <= 4) return token;
    return '${token.substring(0, 4)}****';
  }

  // ── Switch Agency ──
  Future<void> _onConfirmSwitch() async {
    if (_selectedAgency == null) {
      _showToast('Please select an agency', isError: true);
      return;
    }

    // Confirmation dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Switch Agency',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
        ),
        content: Text(
          'Switch to ${_selectedAgency!.name}? The device will require admin approval again.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // Check internet connectivity
    final conn = await Connectivity().checkConnectivity();
    final hasNet = !conn.contains(ConnectivityResult.none);
    if (!hasNet) {
      _showToast(
        'No internet connection. Please connect and try again.',
        isError: true,
      );
      return;
    }

    setState(() => _isSwitching = true);

    // Disconnect MQTT (publishes {online:false} retained, tears down)
    MqttService().disconnect();

    final result = await RegistrationService().switchAgency(
      _selectedAgency!.id,
    );

    if (!mounted) return;

    if (result.success) {
      context.go(AppRoutes.bootScreen);
    } else {
      setState(() => _isSwitching = false);
      _showToast('Switch failed. Please try again.', isError: true);
    }
  }

  // ── Reconnect MQTT ──
  Future<void> _handleReconnect() async {
    setState(() => _isReconnecting = true);

    MqttService().manualReconnect();

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final connected = MqttService().isConnected;
    setState(() {
      _isOnline = connected;
      _isReconnecting = false;
    });

    _showToast(
      connected ? 'Connected' : 'Reconnect failed',
      isError: !connected,
    );
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CustomIconWidget(
              iconName: isError ? 'error_outline' : 'check_circle',
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.cardLight,
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: IconButton(
          icon: const CustomIconWidget(
            iconName: 'arrow_back',
            size: 22,
            color: Color(0xFF1E293B),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1) Profile Section ──
                  _buildProfileSection(),
                  const SizedBox(height: 20),

                  // ── 2) Agency Card ──
                  _buildAgencyCard(),
                  const SizedBox(height: 20),

                  // ── 3) Switch Agency ──
                  _buildSwitchAgencySection(),
                  const SizedBox(height: 20),

                  // ── 4) Reconnect MQTT ──
                  _buildReconnectButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────
  // 1) Profile Section
  // ─────────────────────────────────────────────
  Widget _buildProfileSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // Round avatar
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryContainer,
            ),
            child: const CustomIconWidget(
              iconName: 'account_circle',
              size: 56,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),

          // Device Name — large bold
          Text(
            _deviceName,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 6),

          // Device ID — small monospace
          Text(
            _deviceId,
            style: GoogleFonts.sourceCodePro(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 14),

          // Status chip
          _buildStatusChip(),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _isOnline ? AppTheme.successContainer : AppTheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnline
              ? AppTheme.success.withAlpha(102)
              : AppTheme.errorColor.withAlpha(102),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isOnline ? AppTheme.success : AppTheme.errorColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isOnline ? 'ONLINE' : 'OFFLINE',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _isOnline ? AppTheme.success : AppTheme.errorColor,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 2) Agency Card
  // ─────────────────────────────────────────────
  Widget _buildAgencyCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const CustomIconWidget(
                  iconName: 'business',
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Agency',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Agency Name
          _buildInfoRow(
            icon: 'domain',
            label: 'Agency Name',
            value: _agencyName,
          ),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Color(0xFFEEF2F7),
          ),

          // Agency Code — badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const CustomIconWidget(
                  iconName: 'tag',
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Agency Code',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withAlpha(77)),
                  ),
                  child: Text(
                    _agencyCode,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Color(0xFFEEF2F7),
          ),

          // Agency Token — masked
          _buildInfoRow(
            icon: 'vpn_key',
            label: 'Agency Token',
            value: _maskToken(_agencyToken),
            valueStyle: GoogleFonts.sourceCodePro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CustomIconWidget(
            iconName: icon,
            size: 18,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style:
                  valueStyle ??
                  GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 3) Switch Agency Section
  // ─────────────────────────────────────────────
  Widget _buildSwitchAgencySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              const CustomIconWidget(
                iconName: 'swap_horiz',
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Switch Agency',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dropdown + Confirm button row
          Row(
            children: [
              // Dropdown — Expanded
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AgencyOption>(
                      value: _selectedAgency,
                      isExpanded: true,
                      hint: Text(
                        _agencies.isEmpty
                            ? 'No agencies available'
                            : 'Select agency',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: _isSwitching || _agencies.isEmpty
                          ? null
                          : (val) => setState(() => _selectedAgency = val),
                      items: _agencies
                          .map(
                            (a) => DropdownMenuItem<AgencyOption>(
                              value: a,
                              child: Text(
                                '${a.name} (${a.code})',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Confirm button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSwitching ? null : _onConfirmSwitch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.primary.withAlpha(153),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSwitching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Confirm',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 4) Reconnect MQTT Button
  // ─────────────────────────────────────────────
  Widget _buildReconnectButton() {
    // Disabled when online OR reconnecting
    final bool disabled = _isOnline || _isReconnecting;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: disabled ? null : _handleReconnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withAlpha(102),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isReconnecting
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Connecting...',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomIconWidget(
                    iconName: 'wifi_tethering',
                    size: 20,
                    color: disabled
                        ? Colors.white.withAlpha(153)
                        : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reconnect MQTT',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: disabled
                          ? Colors.white.withAlpha(153)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
