import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';

import '../../../core/services/ble_connection_service.dart';
import '../../../core/services/modbus_storage_service.dart';
import '../../../core/services/wifi_connection_cache.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum ModbusConnectionType { wifi, bluetooth }

class ModbusDevice {
  final String id;
  final String name;
  final String address; // IP for wifi, MAC for BT
  final int port; // untuk WiFi (default 502); diabaikan untuk BT
  final ModbusConnectionType connectionType;
  final bool isConnected;
  final int slaveId;
  final String functionCode;
  final String dataType;
  final String byteOrder;
  final int startAddress; // ← TAMBAH
  final int registerCount; // ← TAMBAH
  /// Pembahagi nilai register (1 = tiada skala; 10 = nilai ÷10, zoom out).
  final double scale;
  final List<ModbusRegisterValue> registerValues;

  const ModbusDevice({
    required this.id,
    required this.name,
    required this.address,
    this.port = 502,
    required this.connectionType,
    required this.isConnected,
    required this.slaveId,
    required this.functionCode,
    required this.dataType,
    required this.byteOrder,
    this.startAddress = 0, // ← TAMBAH
    this.registerCount = 2, // ← TAMBAH
    this.scale = 1,
    this.registerValues = const [],
  });

  ModbusDevice copyWith({
    String? id,
    String? name,
    String? address,
    int? port,
    ModbusConnectionType? connectionType,
    bool? isConnected,
    int? slaveId,
    String? functionCode,
    String? dataType,
    String? byteOrder,
    List<ModbusRegisterValue>? registerValues,
    int? startAddress,
    int? registerCount,
    double? scale,
  }) {
    return ModbusDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      connectionType: connectionType ?? this.connectionType,
      isConnected: isConnected ?? this.isConnected,
      slaveId: slaveId ?? this.slaveId,
      functionCode: functionCode ?? this.functionCode,
      dataType: dataType ?? this.dataType,
      byteOrder: byteOrder ?? this.byteOrder,
      registerValues: registerValues ?? this.registerValues,
      startAddress: startAddress ?? this.startAddress,
      registerCount: registerCount ?? this.registerCount,
      scale: scale ?? this.scale,
    );
  }
}

class ModbusRegisterValue {
  final String address;
  final String value;
  final String unit;

  const ModbusRegisterValue({
    required this.address,
    required this.value,
    this.unit = '',
  });
}

class ModbusDevicePanelWidget extends StatefulWidget {
  const ModbusDevicePanelWidget({super.key});

  @override
  State<ModbusDevicePanelWidget> createState() =>
      _ModbusDevicePanelWidgetState();
}

class _ModbusDevicePanelWidgetState extends State<ModbusDevicePanelWidget>
    with WidgetsBindingObserver {
  final _storage = ModbusStorageService();

  List<ModbusDevice> _devices = [];
  // final Set<String> _expandedIds = {'dev-1'};
  final Set<String> _expandedIds = {};
  ModbusConnectionType? _filterType; // null = all

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDevices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLinkStatuses();
    }
  }

  void _refreshLinkStatuses() {
    if (!mounted) return;
    setState(() {
      _devices = _devices.map(_withLinkStatus).toList();
    });
  }

  Future<void> _loadDevices() async {
    final saved = await _storage.getAll();
    if (mounted) {
      setState(() => _devices = saved.map(_withLinkStatus).toList());
    }
  }

  /// Hijau bila transport cache atau stack BLE masih connected.
  bool _hasActiveLink(ModbusDevice d) {
    if (d.connectionType == ModbusConnectionType.bluetooth) {
      if (BleConnectionService().activeFor(d.address) != null) return true;
      final want = BleConnectionService.normBleAddress(d.address);
      for (final dev in FlutterBluePlus.connectedDevices) {
        try {
          if (BleConnectionService.normBleAddress(dev.remoteId.str) == want) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    }
    return WifiConnectionCache().activeFor(d.address, d.port) != null;
  }

  ModbusDevice _withLinkStatus(ModbusDevice d) =>
      d.copyWith(isConnected: _hasActiveLink(d));

  List<ModbusDevice> get _filteredDevices {
    if (_filterType == null) return _devices;
    return _devices.where((d) => d.connectionType == _filterType).toList();
  }

  int get _wifiCount => _devices
      .where((d) => d.connectionType == ModbusConnectionType.wifi)
      .length;
  int get _btCount => _devices
      .where((d) => d.connectionType == ModbusConnectionType.bluetooth)
      .length;

  void _onAddDevice() async {
    // Step 1: pick source
    final source = await _showSourcePickerDialog();
    if (source == null || !mounted) return;

    // Step 2: connect dulu (BT scan/connect ATAU WiFi ip/port), dapatkan address.
    String? verifiedAddress;
    int verifiedPort = 502;
    if (source == ModbusConnectionType.bluetooth) {
      verifiedAddress = await _scanAndConnectBle();
    } else {
      final w = await _connectWifi();
      if (w != null) {
        verifiedAddress = w.ip;
        verifiedPort = w.port;
      }
    }
    if (verifiedAddress == null || !mounted) return;

    // Step 3: show modbus settings dialog (address readonly, auto-isi).
    final result = await _showModbusSettingsDialog(
      context: context,
      connectionType: source,
      existingDevice: null,
      prefilledAddress: verifiedAddress,
    );
    if (result == null || !mounted) return;

    final addr = source == ModbusConnectionType.bluetooth
        ? (result['address'] as String).trim().toUpperCase()
        : (result['address'] as String).trim();
    if (await _storage.exists(addr, source)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device dengan address "$addr" dah wujud'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    var newDevice = _withLinkStatus(
      ModbusDevice(
        id: 'dev-${DateTime.now().millisecondsSinceEpoch}',
        name: result['name'] as String,
        address: addr,
        port: verifiedPort,
        connectionType: source,
        isConnected: false,
        slaveId: result['slaveId'] as int,
        functionCode: result['functionCode'] as String,
        dataType: result['dataType'] as String,
        byteOrder: result['byteOrder'] as String,
        startAddress: result['startAddress'] as int,
        registerCount: result['registerCount'] as int,
        scale: result['scale'] as double,
        registerValues: const [],
      ),
    );
    // Flow tambah: sambungan sudah diuji — hijau sehingga putus.
    if (!newDevice.isConnected) {
      newDevice = newDevice.copyWith(isConnected: true);
    }

    await _storage.add(newDevice);
    setState(() => _devices = [..._devices, newDevice]);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device "${result['name']}" added'),
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

  void _onEditDevice(ModbusDevice device) async {
    final result = await _showModbusSettingsDialog(
      context: context,
      connectionType: device.connectionType,
      existingDevice: device,
    );
    if (result == null || !mounted) return;

    final updated = device.copyWith(
      name: result['name'] as String,
      address: result['address'] as String,
      slaveId: result['slaveId'] as int,
      functionCode: result['functionCode'] as String,
      dataType: result['dataType'] as String,
      byteOrder: result['byteOrder'] as String,
      startAddress: result['startAddress'] as int,
      registerCount: result['registerCount'] as int,
      scale: result['scale'] as double,
    );
    await _storage.update(updated);
    setState(() {
      _devices = _devices.map((d) => d.id == device.id ? updated : d).toList();
    });
  }

  Future<void> _onTransmitDevice(ModbusDevice device) async {
    await context.push(AppRoutes.modbusTransmissionScreen, extra: device);
    if (mounted) _refreshLinkStatuses();
  }

  void _onDeleteDevice(ModbusDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Remove "${device.name}" from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _storage.remove(device.id);
      setState(() {
        _expandedIds.remove(device.id);
        _devices = _devices.where((d) => d.id != device.id).toList();
      });
    }
  }

  /// Scan BLE, pilih device, connect+discover. Pulang MAC kalau berjaya.
  Future<String?> _scanAndConnectBle() async {
    final svc = BleConnectionService();
    if (!await svc.ensureReady()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth tidak aktif')),
        );
      }
      return null;
    }
    final selected = await showDialog<BleScanItem>(
      context: context,
      builder: (ctx) => _BleScanDialog(service: svc),
    );
    if (selected == null || !mounted) return null;

    // Connect + discover (papar loading).
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Connecting…'),
        ]),
      ),
    );
    final res = await svc.connectDevice(selected.device);
    if (mounted) Navigator.pop(context); // tutup loading
    if (!res.ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.error ?? 'Sambungan gagal')),
        );
      }
      return null;
    }
    return selected.mac; // MAC/remoteId (selamat jika remoteId.str null)
  }

  /// Dialog IP/port, test connect TCP. Pulang (ip, port) kalau berjaya.
  Future<({String ip, int port})?> _connectWifi() async {
    final input = await showDialog<({String ip, int port})>(
      context: context,
      builder: (ctx) => const _WifiConnectDialog(),
    );
    if (input == null || !mounted) return null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Connecting…'),
        ]),
      ),
    );
    final res = await WifiConnectionCache().connect(input.ip, input.port);
    if (mounted) Navigator.pop(context);
    if (!res.ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.error ?? 'Sambungan gagal')),
        );
      }
      return null;
    }
    return (ip: input.ip, port: input.port);
  }

  Future<ModbusConnectionType?> _showSourcePickerDialog() {
    return showDialog<ModbusConnectionType>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Select Connection Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SourceOption(
                icon: 'wifi',
                label: 'WiFi / TCP',
                subtitle: 'Connect via IP address',
                color: AppTheme.primary,
                onTap: () => Navigator.pop(ctx, ModbusConnectionType.wifi),
              ),
              const SizedBox(height: 10),
              _SourceOption(
                icon: 'bluetooth',
                label: 'Bluetooth',
                subtitle: 'Connect via MAC address',
                color: const Color(0xFF7C3AED),
                onTap: () => Navigator.pop(ctx, ModbusConnectionType.bluetooth),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showModbusSettingsDialog({
    required BuildContext context,
    required ModbusConnectionType connectionType,
    ModbusDevice? existingDevice,
    String? prefilledAddress,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModbusSettingsDialog(
        connectionType: connectionType,
        existingDevice: existingDevice,
        prefilledAddress: prefilledAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredDevices;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: CustomIconWidget(
                      iconName: 'device_hub',
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modbus Devices',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_devices.where((d) => d.isConnected).length} connected · ${_devices.length} total',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Filter bar + Add button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                // WiFi filter chip
                _FilterChip(
                  icon: 'wifi',
                  label: 'WiFi',
                  count: _wifiCount,
                  color: AppTheme.primary,
                  isSelected: _filterType == ModbusConnectionType.wifi,
                  onTap: () => setState(() {
                    _filterType = _filterType == ModbusConnectionType.wifi
                        ? null
                        : ModbusConnectionType.wifi;
                  }),
                ),
                const SizedBox(width: 6),
                // BT filter chip
                _FilterChip(
                  icon: 'bluetooth',
                  label: 'BT',
                  count: _btCount,
                  color: const Color(0xFF7C3AED),
                  isSelected: _filterType == ModbusConnectionType.bluetooth,
                  onTap: () => setState(() {
                    _filterType = _filterType == ModbusConnectionType.bluetooth
                        ? null
                        : ModbusConnectionType.bluetooth;
                  }),
                ),
                const Spacer(),
                // Add button — inline with filters
                FilledButton.icon(
                  onPressed: _onAddDevice,
                  icon: CustomIconWidget(
                    iconName: 'add',
                    color: Colors.white,
                    size: 16,
                  ),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                    textStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    CustomIconWidget(
                      iconName: 'device_hub',
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No devices. Tap Add to connect.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) {
                final device = filtered[index];
                final isExpanded = _expandedIds.contains(device.id);
                return _DeviceTile(
                  device: device,
                  isExpanded: isExpanded,
                  onToggle: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(device.id);
                      } else {
                        _expandedIds.add(device.id);
                      }
                    });
                  },
                  onTransmit: () => _onTransmitDevice(device),
                  onEdit: () => _onEditDevice(device),
                  onDelete: () => _onDeleteDevice(device),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String icon;
  final String label;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withAlpha(30)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomIconWidget(iconName: icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              '$label ($count)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Source Option ────────────────────────────────────────────────────────────

class _SourceOption extends StatelessWidget {
  final String icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CustomIconWidget(iconName: icon, color: color, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            CustomIconWidget(
              iconName: 'chevron_right',
              color: theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Device Tile ─────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final ModbusDevice device;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onTransmit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceTile({
    required this.device,
    required this.isExpanded,
    required this.onToggle,
    required this.onTransmit,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _connColor => device.connectionType == ModbusConnectionType.wifi
      ? AppTheme.primary
      : const Color(0xFF7C3AED);

  String get _connIcon =>
      device.connectionType == ModbusConnectionType.wifi ? 'wifi' : 'bluetooth';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValues = device.isConnected && device.registerValues.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status dot (merah/hijau) — dimatikan buat masa ini
              // Padding(
              //   padding: const EdgeInsets.only(top: 4),
              //   child: Container(
              //     width: 8,
              //     height: 8,
              //     decoration: BoxDecoration(
              //       color: device.isConnected
              //           ? AppTheme.success
              //           : AppTheme.errorColor,
              //       shape: BoxShape.circle,
              //       boxShadow: device.isConnected
              //           ? [
              //               BoxShadow(
              //                 color: AppTheme.success.withAlpha(100),
              //                 blurRadius: 4,
              //                 spreadRadius: 1,
              //               ),
              //             ]
              //           : null,
              //     ),
              //   ),
              // ),
              // const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Baris 1: ikon + tajuk (2 baris: nama, IP/MAC)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _connColor.withAlpha(24),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: CustomIconWidget(
                              iconName: _connIcon,
                              color: _connColor,
                              size: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                device.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 8,
                                  color: _connColor,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Baris 2: ID, FC, jenis data, byte order
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _SubtitleChip(
                          label: 'ID:${device.slaveId}',
                          theme: theme,
                          color: theme.colorScheme.primary,
                        ),
                        _SubtitleChip(
                            label: device.functionCode, theme: theme),
                        _SubtitleChip(label: device.dataType, theme: theme),
                        _SubtitleChip(
                          label: device.byteOrder.split(' ').first,
                          theme: theme,
                        ),
                      ],
                    ),
                    // Baris 3: IP / MAC — dipindah ke subtitle tajuk (di atas)
                    // const SizedBox(height: 4),
                    // Text(
                    //   device.address,
                    //   maxLines: 1,
                    //   overflow: TextOverflow.ellipsis,
                    //   style: theme.textTheme.labelSmall?.copyWith(
                    //     fontSize: 10,
                    //     color: _connColor,
                    //     fontWeight: FontWeight.w600,
                    //     letterSpacing: 0.2,
                    //   ),
                    // ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Transmit, Edit, Delete, Dropdown icons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Transmit',
                    child: GestureDetector(
                      onTap: onTransmit,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CustomIconWidget(
                          iconName: 'send',
                          color: AppTheme.primary,
                          size: 17,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CustomIconWidget(
                        iconName: 'edit',
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 17,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CustomIconWidget(
                        iconName: 'delete',
                        color: AppTheme.errorColor.withAlpha(180),
                        size: 17,
                      ),
                    ),
                  ),
                  if (hasValues)
                    GestureDetector(
                      onTap: onToggle,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: CustomIconWidget(
                            iconName: 'keyboard_arrow_down',
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Expanded register values
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: hasValues && isExpanded
              ? Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                      80,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REGISTER VALUES',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...device.registerValues.map(
                        (reg) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              // Address on the left
                              CustomIconWidget(
                                iconName: 'memory',
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                reg.address,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontFeatures: [
                                    const FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Value on the right
                              Text(
                                reg.value,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                  fontFeatures: [
                                    const FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SubtitleChip extends StatelessWidget {
  final String label;
  final ThemeData theme;
  final Color? color;

  const _SubtitleChip({required this.label, required this.theme, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: c,
          fontWeight: FontWeight.w500,
          fontSize: 10,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─── Modbus Settings Dialog ───────────────────────────────────────────────────

class _ModbusSettingsDialog extends StatefulWidget {
  final ModbusConnectionType connectionType;
  final ModbusDevice? existingDevice;
  final String? prefilledAddress;

  const _ModbusSettingsDialog({
    required this.connectionType,
    this.existingDevice,
    this.prefilledAddress,
  });

  @override
  State<_ModbusSettingsDialog> createState() => _ModbusSettingsDialogState();
}

class _ModbusSettingsDialogState extends State<_ModbusSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _slaveIdCtrl;
  late final TextEditingController _startAddrCtrl;
  late final TextEditingController _lengthCtrl;
  late final TextEditingController _timeoutCtrl;
  late final TextEditingController _scaleCtrl;

  late String _selectedFunctionCode;
  late String _selectedDataType;
  late String _selectedByteOrder;

  final _functionCodes = [
    'FC01',
    'FC02',
    'FC03',
    'FC04',
    'FC05',
    'FC06',
    'FC16',
  ];
  final _dataTypes = [
    'INT16',
    'UINT16',
    'INT32',
    'UINT32',
    'FLOAT32',
    'FLOAT64',
    'BOOL',
  ];
  final _byteOrders = [
    'Big Endian',
    'Little Endian',
    'Big Endian Swap',
    'Little Endian Swap',
  ];

  bool get _isWifi => widget.connectionType == ModbusConnectionType.wifi;

  int _parseAddr(String s) {
    final t = s.trim();
    if (t.toLowerCase().startsWith('0x')) {
      return int.tryParse(t.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(t) ?? 0;
  }

  double _parseScale(String s) {
    final v = double.tryParse(s.trim());
    if (v == null || v <= 0) return 1;
    return v;
  }

  String _formatScale(double scale) {
    if (scale == scale.roundToDouble()) return scale.toInt().toString();
    return scale.toString();
  }

  @override
  void initState() {
    super.initState();
    final d = widget.existingDevice;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _addressCtrl = TextEditingController(
      text: widget.prefilledAddress ??
          d?.address ??
          (_isWifi ? '192.168.1.' : 'AA:BB:CC:DD:EE:FF'),
    );
    _slaveIdCtrl = TextEditingController(text: d?.slaveId.toString() ?? '1');
    _startAddrCtrl = TextEditingController(
      text: d != null
          ? '0x${d.startAddress.toRadixString(16).padLeft(4, '0').toUpperCase()}'
          : '0x0000',
    );
    _lengthCtrl = TextEditingController(text: d?.registerCount.toString() ?? '10');
    _timeoutCtrl = TextEditingController(text: '1000');
    _scaleCtrl = TextEditingController(text: _formatScale(d?.scale ?? 1));
    _selectedFunctionCode = d?.functionCode ?? 'FC03';
    _selectedDataType = d?.dataType ?? 'INT16';
    _selectedByteOrder = d?.byteOrder ?? 'Big Endian';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _slaveIdCtrl.dispose();
    _startAddrCtrl.dispose();
    _lengthCtrl.dispose();
    _timeoutCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'slaveId': int.tryParse(_slaveIdCtrl.text) ?? 1,
      'functionCode': _selectedFunctionCode,
      'dataType': _selectedDataType,
      'byteOrder': _selectedByteOrder,
      'startAddress': _parseAddr(_startAddrCtrl.text), // ← TAMBAH
      'registerCount': int.tryParse(_lengthCtrl.text) ?? 2, // ← TAMBAH
      'scale': _parseScale(_scaleCtrl.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existingDevice != null;
    final connColor = _isWifi ? AppTheme.primary : const Color(0xFF7C3AED);
    final connIcon = _isWifi ? 'wifi' : 'bluetooth';
    final connLabel = _isWifi ? 'WiFi / TCP' : 'Bluetooth';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dialog header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              decoration: BoxDecoration(
                color: connColor.withAlpha(18),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: connColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: connIcon,
                        color: connColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit Device' : 'Add Device',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          connLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: connColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: CustomIconWidget(
                      iconName: 'close',
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DialogSectionLabel(label: 'Device Info', theme: theme),
                      const SizedBox(height: 10),
                      _DialogField(
                        label: 'Device Name',
                        hint: 'e.g. RTU Sensor A',
                        controller: _nameCtrl,
                        icon: 'label',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        label: _isWifi ? 'IP Address' : 'MAC Address',
                        hint: _isWifi ? '192.168.1.x' : 'AA:BB:CC:DD:EE:FF',
                        controller: _addressCtrl,
                        icon: _isWifi ? 'lan' : 'bluetooth',
                        readOnly: widget.prefilledAddress != null ||
                            widget.existingDevice != null,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      _DialogSectionLabel(
                        label: 'Modbus Parameters',
                        theme: theme,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogField(
                              label: 'Slave ID',
                              hint: '1–247',
                              controller: _slaveIdCtrl,
                              icon: 'tag',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DialogField(
                              label: 'Start Address',
                              hint: '0x0000',
                              controller: _startAddrCtrl,
                              icon: 'pin',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogField(
                              label: 'Length',
                              hint: '10',
                              controller: _lengthCtrl,
                              icon: 'format_list_numbered',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DialogField(
                              label: 'Timeout (ms)',
                              hint: '1000',
                              controller: _timeoutCtrl,
                              icon: 'timer',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        label: 'Scale (zoom out ÷)',
                        hint: '1 = tiada, 10 = ÷10',
                        controller: _scaleCtrl,
                        icon: 'zoom_out',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DialogDropdown(
                        label: 'Function Code',
                        value: _selectedFunctionCode,
                        items: _functionCodes,
                        icon: 'code',
                        onChanged: (v) =>
                            setState(() => _selectedFunctionCode = v!),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogDropdown(
                              label: 'Data Type',
                              value: _selectedDataType,
                              items: _dataTypes,
                              icon: 'data_object',
                              onChanged: (v) =>
                                  setState(() => _selectedDataType = v!),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DialogDropdown(
                              label: 'Byte Order',
                              value: _selectedByteOrder,
                              items: _byteOrders,
                              icon: 'swap_horiz',
                              onChanged: (v) =>
                                  setState(() => _selectedByteOrder = v!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _onSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : CustomIconWidget(
                              iconName: 'save',
                              color: Colors.white,
                              size: 16,
                            ),
                      label: Text(_isSaving ? 'Saving…' : 'Save & Add'),
                      style: FilledButton.styleFrom(
                        backgroundColor: connColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSectionLabel extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _DialogSectionLabel({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final bool readOnly;

  const _DialogField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 17,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}

class _DialogDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final String icon;
  final ValueChanged<String?> onChanged;

  const _DialogDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 17,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ── Dialog: senarai scan BLE ────────────────────────────────────────────────
class _BleScanDialog extends StatefulWidget {
  final BleConnectionService service;
  const _BleScanDialog({required this.service});
  @override
  State<_BleScanDialog> createState() => _BleScanDialogState();
}

class _BleScanDialogState extends State<_BleScanDialog> {
  List<BleScanItem> _items = [];
  bool _scanning = true;
  String? _error;
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;

  @override
  void initState() {
    super.initState();
    _resultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        if (!mounted) return;
        setState(() {
          _items = BleConnectionService.mapScanResults(results);
        });
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _error = e.toString();
          });
        }
      },
    );
    _scanningSub = FlutterBluePlus.isScanning.listen((active) {
      if (mounted) setState(() => _scanning = active);
    });
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _items = [];
    });
    try {
      await widget.service.startDeviceScan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _scanningSub?.cancel();
    widget.service.cancelScanSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // titlePadding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
      // contentPadding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
      // actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(
        children: [
          const Text('Pilih Peranti BLE'),
          const Spacer(),
          if (_scanning)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _scanning ? null : _start,
              tooltip: 'Scan semula',
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.errorColor,
                  ),
                ),
              )
            : _items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _scanning ? 'Mengimbas…' : 'Tiada peranti dijumpai',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.only(left:0, right: 16),
                    // contentPadding: const EdgeInsets.symmetric(horizontal: 13),
                    // minLeadingWidth: 28,
                    // horizontalTitleGap: 8,
                    leading: Icon(
                      Icons.bluetooth,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      it.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.mac,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            letterSpacing: 0.2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          it.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      '${it.rssi}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, it),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}

// ── Dialog: input IP/port WiFi ──────────────────────────────────────────────
class _WifiConnectDialog extends StatefulWidget {
  const _WifiConnectDialog();
  @override
  State<_WifiConnectDialog> createState() => _WifiConnectDialogState();
}

class _WifiConnectDialogState extends State<_WifiConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ipCtrl = TextEditingController(text: '192.168.1.');
  final _portCtrl = TextEditingController(text: '502');

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (
      ip: _ipCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 502,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sambung WiFi / TCP'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _ipCtrl,
              decoration: const InputDecoration(labelText: 'IP Address', hintText: '192.168.1.x'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port', hintText: '502'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _ok, child: const Text('Sambung')),
      ],
    );
  }
}
