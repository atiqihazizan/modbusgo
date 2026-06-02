import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/local_storage_service.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- Data ---
  String _deviceName = '';
  String _deviceId = '';
  String _agencyName = '';
  String _agencyCode = '';
  String _agencyToken = '';
  bool _isOnline = false;
  bool _isLoading = true;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen to MQTT connection changes
    MqttService().onConnectionChanged = (connected) {
      if (mounted) setState(() => _isOnline = connected);
    };
  }

  @override
  void dispose() {
    // Remove listener to avoid stale callback
    MqttService().onConnectionChanged = null;
    super.dispose();
  }

  Future<void> _loadData() async {
    final storage = LocalStorageService();
    final deviceInfo = await storage.getDeviceInfo();
    final agencyName = await storage.getAgencyName();
    final agencyCode = await storage.getAgencyCode();
    final agencyToken = await storage.getAgencyToken();
    final deviceId = await DeviceIdentityService().getDeviceId();

    if (mounted) {
      setState(() {
        _deviceName = deviceInfo?['name'] ?? 'Unknown Device';
        _deviceId = deviceInfo?['device_id'] ?? deviceId;
        _agencyName = agencyName ?? '-';
        _agencyCode = agencyCode ?? '-';
        _agencyToken = agencyToken ?? '';
        _isOnline = MqttService().isConnected;
        _isLoading = false;
      });
    }
  }

  String _maskToken(String token) {
    if (token.isEmpty) return '-';
    if (token.length <= 4) return token;
    return '${token.substring(0, 4)}****';
  }

  Future<void> _handleReconnect() async {
    setState(() => _isReconnecting = true);

    MqttService().manualReconnect();

    // Wait 2 seconds for connection attempt
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final connected = MqttService().isConnected;
    setState(() {
      _isOnline = connected;
      _isReconnecting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CustomIconWidget(
              iconName: connected ? 'check_circle' : 'error_outline',
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              connected ? 'Connected' : 'Gagal sambung',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: connected ? AppTheme.success : AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  // ── SECTION 1: Profile ──
                  _buildProfileSection(colorScheme),
                  const SizedBox(height: 20),

                  // ── SECTION 2: Agency Card ──
                  _buildAgencyCard(colorScheme),
                  const SizedBox(height: 24),

                  // ── SECTION 3: Reconnect Button ──
                  _buildReconnectButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────
  // Profile Section
  // ─────────────────────────────────────────────
  Widget _buildProfileSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
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

          // Device Name
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

          // Device ID — monospace
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

          // MQTT Status Chip
          _buildMqttChip(),
        ],
      ),
    );
  }

  Widget _buildMqttChip() {
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
  // Agency Card
  // ─────────────────────────────────────────────
  Widget _buildAgencyCard(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
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

          // Agency Code
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

          // Agency Token (masked)
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
  // Reconnect Button
  // ─────────────────────────────────────────────
  Widget _buildReconnectButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isReconnecting ? null : _handleReconnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withAlpha(153),
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
                  const CustomIconWidget(
                    iconName: 'wifi_tethering',
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reconnect MQTT',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
