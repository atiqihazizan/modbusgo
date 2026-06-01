import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/custom_icon_widget.dart';

enum ModbusConnectionType { wifi, bluetooth }

class ModbusDevice {
  final String id;
  final String name;
  final String address; // IP for wifi, MAC for BT
  final ModbusConnectionType connectionType;
  final bool isConnected;
  final int slaveId;
  final String functionCode;
  final String dataType;
  final String byteOrder;
  final List<ModbusRegisterValue> registerValues;

  const ModbusDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.connectionType,
    required this.isConnected,
    required this.slaveId,
    required this.functionCode,
    required this.dataType,
    required this.byteOrder,
    this.registerValues = const [],
  });

  ModbusDevice copyWith({
    String? id,
    String? name,
    String? address,
    ModbusConnectionType? connectionType,
    bool? isConnected,
    int? slaveId,
    String? functionCode,
    String? dataType,
    String? byteOrder,
    List<ModbusRegisterValue>? registerValues,
  }) {
    return ModbusDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      connectionType: connectionType ?? this.connectionType,
      isConnected: isConnected ?? this.isConnected,
      slaveId: slaveId ?? this.slaveId,
      functionCode: functionCode ?? this.functionCode,
      dataType: dataType ?? this.dataType,
      byteOrder: byteOrder ?? this.byteOrder,
      registerValues: registerValues ?? this.registerValues,
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

// Mock initial data
final _initialDevices = [
  ModbusDevice(
    id: 'dev-1',
    name: 'RTU Sensor A',
    address: '192.168.1.101',
    connectionType: ModbusConnectionType.wifi,
    isConnected: true,
    slaveId: 1,
    functionCode: 'FC03',
    dataType: 'INT16',
    byteOrder: 'Big Endian',
    registerValues: [
      ModbusRegisterValue(address: '0x0001', value: '1024', unit: 'raw'),
      ModbusRegisterValue(address: '0x0002', value: '23.5', unit: '°C'),
      ModbusRegisterValue(address: '0x0003', value: '65', unit: '%'),
    ],
  ),
  ModbusDevice(
    id: 'dev-2',
    name: 'BT Module B',
    address: 'AA:BB:CC:DD:EE:FF',
    connectionType: ModbusConnectionType.bluetooth,
    isConnected: true,
    slaveId: 2,
    functionCode: 'FC04',
    dataType: 'FLOAT32',
    byteOrder: 'Little Endian',
    registerValues: [
      ModbusRegisterValue(address: '0x0010', value: '512', unit: 'raw'),
      ModbusRegisterValue(address: '0x0011', value: '4.95', unit: 'V'),
    ],
  ),
];

class ModbusDevicePanelWidget extends StatefulWidget {
  const ModbusDevicePanelWidget({super.key});

  @override
  State<ModbusDevicePanelWidget> createState() =>
      _ModbusDevicePanelWidgetState();
}

class _ModbusDevicePanelWidgetState extends State<ModbusDevicePanelWidget> {
  List<ModbusDevice> _devices = List.from(_initialDevices);
  final Set<String> _expandedIds = {'dev-1'};
  ModbusConnectionType? _filterType; // null = all

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

    // Step 2: show modbus settings dialog
    final result = await _showModbusSettingsDialog(
      context: context,
      connectionType: source,
      existingDevice: null,
    );
    if (result == null || !mounted) return;

    setState(() {
      _devices = [
        ..._devices,
        ModbusDevice(
          id: 'dev-${DateTime.now().millisecondsSinceEpoch}',
          name: result['name'] as String,
          address: result['address'] as String,
          connectionType: source,
          isConnected: false,
          slaveId: result['slaveId'] as int,
          functionCode: result['functionCode'] as String,
          dataType: result['dataType'] as String,
          byteOrder: result['byteOrder'] as String,
          registerValues: const [],
        ),
      ];
    });

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

    setState(() {
      _devices = _devices.map((d) {
        if (d.id == device.id) {
          return d.copyWith(
            name: result['name'] as String,
            address: result['address'] as String,
            slaveId: result['slaveId'] as int,
            functionCode: result['functionCode'] as String,
            dataType: result['dataType'] as String,
            byteOrder: result['byteOrder'] as String,
          );
        }
        return d;
      }).toList();
    });
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
      setState(() {
        _expandedIds.remove(device.id);
        _devices = _devices.where((d) => d.id != device.id).toList();
      });
    }
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
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModbusSettingsDialog(
        connectionType: connectionType,
        existingDevice: existingDevice,
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceTile({
    required this.device,
    required this.isExpanded,
    required this.onToggle,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status dot
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.isConnected
                        ? AppTheme.success
                        : AppTheme.errorColor,
                    shape: BoxShape.circle,
                    boxShadow: device.isConnected
                        ? [
                            BoxShadow(
                              color: AppTheme.success.withAlpha(100),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Connection type icon
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
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Subtitle: slave ID + protocol params + address
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        _SubtitleChip(
                          label: 'ID:${device.slaveId}',
                          theme: theme,
                          color: theme.colorScheme.primary,
                        ),
                        _SubtitleChip(label: device.functionCode, theme: theme),
                        _SubtitleChip(label: device.dataType, theme: theme),
                        _SubtitleChip(
                          label: device.byteOrder.split(' ').first,
                          theme: theme,
                        ),
                        _SubtitleChip(
                          label: device.address,
                          theme: theme,
                          color: _connColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Edit, Delete, Dropdown icons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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

  const _ModbusSettingsDialog({
    required this.connectionType,
    this.existingDevice,
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

  @override
  void initState() {
    super.initState();
    final d = widget.existingDevice;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _addressCtrl = TextEditingController(
      text: d?.address ?? (_isWifi ? '192.168.1.' : 'AA:BB:CC:DD:EE:FF'),
    );
    _slaveIdCtrl = TextEditingController(text: d?.slaveId.toString() ?? '1');
    _startAddrCtrl = TextEditingController(text: '0x0000');
    _lengthCtrl = TextEditingController(text: '10');
    _timeoutCtrl = TextEditingController(text: '1000');
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
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    // TODO: connect real logic — save/connect device
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'slaveId': int.tryParse(_slaveIdCtrl.text) ?? 1,
      'functionCode': _selectedFunctionCode,
      'dataType': _selectedDataType,
      'byteOrder': _selectedByteOrder,
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

  const _DialogField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
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
