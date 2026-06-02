import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/registration_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Mock values — TODO: connect real logic — persist to SharedPreferences
  final _mqttUrlController = TextEditingController(
    text: 'mqtt://broker.modbusgo.io:1883',
  );
  final _mqttTopicController = TextEditingController(
    text: 'modbusgo/tracking/JPS-SEL',
  );
  final _mqttClientIdController = TextEditingController(text: 'MBG-2024-0047');
  final _modbusTimeoutController = TextEditingController(text: '3000');
  final _modbusRetryController = TextEditingController(text: '3');
  final _modbusIntervalController = TextEditingController(text: '5000');

  bool _mqttTlsEnabled = false;
  bool _autoReconnect = true;
  bool _isSaving = false;

  // Real data — loaded from storage / package info
  String _deviceName = '—';
  String _deviceId = '—';
  final String _deviceModel = '—'; // no source (phone, not RTU)
  final String _firmwareVersion = '—'; // no source
  String _agencyName = '—';
  String _agencyCode = '—';
  String _agencyToken = '—';
  final String _registeredAt = '—'; // no source (storage not saved)
  String _appVersion = '—';
  String _flutterVersion = '—';

  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final storage = LocalStorageService();
    final info = await storage.getDeviceInfo();
    final agencyName = await storage.getAgencyName();
    final agencyCode = await storage.getAgencyCode();
    final agencyToken = await storage.getAgencyToken();
    final deviceId = await DeviceIdentityService().getDeviceId();

    String appVer = '—';
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVer = '${pkg.version} (build ${pkg.buildNumber})';
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _deviceName = (info?['name']?.isNotEmpty == true) ? info!['name']! : '—';
      _deviceId = deviceId.isNotEmpty ? deviceId : '—';
      _agencyName = (agencyName != null && agencyName.isNotEmpty)
          ? agencyName
          : '—';
      _agencyCode = (agencyCode != null && agencyCode.isNotEmpty)
          ? agencyCode
          : '—';
      _agencyToken = (agencyToken != null && agencyToken.isNotEmpty)
          ? _maskToken(agencyToken)
          : '—';
      _appVersion = appVer;
      _flutterVersion = 'Flutter (see About)';
    });
  }

  // Mask part of token for display.
  String _maskToken(String token) {
    if (token.length <= 8) return '••••';
    return '${token.substring(0, 4)}••••••••${token.substring(token.length - 4)}';
  }

  Future<void> _syncFromBackend() async {
    setState(() => _isSyncing = true);
    final ok = await RegistrationService().restoreFromBackend();
    if (!mounted) return;
    if (ok) {
      await _loadInfo(); // reload latest values from storage
    }
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Data synced from server'
              : 'Sync failed — check connection / registration',
        ),
        backgroundColor: ok ? AppTheme.success : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _mqttUrlController.dispose();
    _mqttTopicController.dispose();
    _mqttClientIdController.dispose();
    _modbusTimeoutController.dispose();
    _modbusRetryController.dispose();
    _modbusIntervalController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    // TODO: connect real logic — persist to SharedPreferences
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              CustomIconWidget(
                iconName: 'check_circle',
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              const Text('Settings saved'),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copyToClipboard(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: CustomIconWidget(
            iconName: 'arrow_back',
            color: theme.colorScheme.onSurface,
            size: 22,
          ),
        ),
        title: Text(
          'Settings',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          _isSyncing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _syncFromBackend,
                  icon: CustomIconWidget(
                    iconName: 'sync',
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  tooltip: 'Sync data from server',
                ),
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton.icon(
                  onPressed: _saveSettings,
                  icon: CustomIconWidget(
                    iconName: 'save',
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                  label: Text(
                    'Save',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // ── MQTT Settings ──────────────────────────────────────
            _SectionHeader(
              icon: 'wifi',
              label: 'MQTT Settings',
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            _SettingsCard(
              children: [
                _TextFieldTile(
                  label: 'Broker URL',
                  hint: 'mqtt://host:port',
                  controller: _mqttUrlController,
                  icon: 'link',
                  keyboardType: TextInputType.url,
                ),
                _Divider(),
                _TextFieldTile(
                  label: 'Topic',
                  hint: 'modbusgo/tracking/...',
                  controller: _mqttTopicController,
                  icon: 'topic',
                ),
                _Divider(),
                _TextFieldTile(
                  label: 'Client ID',
                  hint: 'Device client identifier',
                  controller: _mqttClientIdController,
                  icon: 'badge',
                ),
                _Divider(),
                _SwitchTile(
                  label: 'TLS / SSL',
                  subtitle: 'Encrypt broker connection',
                  icon: 'lock',
                  value: _mqttTlsEnabled,
                  onChanged: (v) => setState(() => _mqttTlsEnabled = v),
                ),
                _Divider(),
                _SwitchTile(
                  label: 'Auto Reconnect',
                  subtitle: 'Reconnect on connection loss',
                  icon: 'sync',
                  value: _autoReconnect,
                  onChanged: (v) => setState(() => _autoReconnect = v),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Modbus Timeout & Retry ─────────────────────────────
            _SectionHeader(
              icon: 'settings_ethernet',
              label: 'Modbus Timeout & Retry',
              color: const Color(0xFFD97706),
            ),
            const SizedBox(height: 8),
            _SettingsCard(
              children: [
                _TextFieldTile(
                  label: 'Request Timeout (ms)',
                  hint: '3000',
                  controller: _modbusTimeoutController,
                  icon: 'timer',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                _Divider(),
                _TextFieldTile(
                  label: 'Retry Count',
                  hint: '3',
                  controller: _modbusRetryController,
                  icon: 'replay',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                _Divider(),
                _TextFieldTile(
                  label: 'Poll Interval (ms)',
                  hint: '5000',
                  controller: _modbusIntervalController,
                  icon: 'schedule',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Device Info ────────────────────────────────────────
            _SectionHeader(
              icon: 'memory',
              label: 'Device Info',
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(height: 8),
            _SettingsCard(
              children: [
                _InfoTile(
                  label: 'Device Name',
                  value: _deviceName,
                  icon: 'devices',
                  onCopy: () => _copyToClipboard(_deviceName, 'Device name'),
                ),
                _Divider(),
                _InfoTile(
                  label: 'Device ID',
                  value: _deviceId,
                  icon: 'fingerprint',
                  onCopy: () => _copyToClipboard(_deviceId, 'Device ID'),
                ),
                _Divider(),
                _InfoTile(
                  label: 'Model',
                  value: _deviceModel,
                  icon: 'developer_board',
                ),
                _Divider(),
                _InfoTile(
                  label: 'Firmware',
                  value: _firmwareVersion,
                  icon: 'system_update',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Agency Details ─────────────────────────────────────
            _SectionHeader(
              icon: 'business',
              label: 'Agency Details',
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 8),
            _SettingsCard(
              children: [
                _InfoTile(
                  label: 'Agency Name',
                  value: _agencyName,
                  icon: 'apartment',
                ),
                _Divider(),
                _InfoTile(
                  label: 'Agency Code',
                  value: _agencyCode,
                  icon: 'tag',
                  onCopy: () => _copyToClipboard(_agencyCode, 'Agency code'),
                ),
                _Divider(),
                _InfoTile(
                  label: 'Agency Token',
                  value: _agencyToken,
                  icon: 'key',
                  onCopy: () => _copyToClipboard(_agencyToken, 'Agency token'),
                ),
                _Divider(),
                _InfoTile(
                  label: 'Registered At',
                  value: _registeredAt,
                  icon: 'event',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── App Version ────────────────────────────────────────
            _SectionHeader(
              icon: 'info',
              label: 'App Version',
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _SettingsCard(
              children: [
                _InfoTile(
                  label: 'App Version',
                  value: _appVersion,
                  icon: 'new_releases',
                ),
                _Divider(),
                _InfoTile(
                  label: 'Framework',
                  value: _flutterVersion,
                  icon: 'flutter_dash',
                ),
                _Divider(),
                _InfoTile(
                  label: 'Build Flavor',
                  value: 'Production',
                  icon: 'verified',
                ),
              ],
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                'ModbusGo © 2025 — All rights reserved',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal helper widgets ──────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CustomIconWidget(iconName: icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 52,
      endIndent: 0,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
    );
  }
}

class _TextFieldTile extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _TextFieldTile({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 0,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final String icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  final VoidCallback? onCopy;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: CustomIconWidget(
                iconName: 'content_copy',
                color: theme.colorScheme.onSurfaceVariant,
                size: 16,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Copy',
            ),
        ],
      ),
    );
  }
}
