import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/modbus_data_format.dart';
import '../../../core/app_export.dart';
import '../../../widgets/common/app_card.dart';

class ModbusSettingsWidget extends StatefulWidget {
  const ModbusSettingsWidget({super.key});

  @override
  State<ModbusSettingsWidget> createState() => _ModbusSettingsWidgetState();
}

class _ModbusSettingsWidgetState extends State<ModbusSettingsWidget> {
  bool _isExpanded = false;
  bool _isSaving = false;

  // Controllers — TODO: persist with SharedPreferences
  final _slaveIdCtrl = TextEditingController(text: '1');
  final _addressCtrl = TextEditingController(text: '0x0000');
  final _lengthCtrl = TextEditingController(text: '10');
  final _timeoutCtrl = TextEditingController(text: '1000');
  final _retryCtrl = TextEditingController(text: '3');

  String _selectedFunctionCode = 'FC03 — Read Holding Registers';
  String _selectedDataFormat = 'decimal';

  final _functionCodes = [
    'FC01 — Read Coils',
    'FC02 — Read Discrete Inputs',
    'FC03 — Read Holding Registers',
    'FC04 — Read Input Registers',
    'FC05 — Write Single Coil',
    'FC06 — Write Single Register',
    'FC16 — Write Multiple Registers',
  ];

  @override
  void dispose() {
    _slaveIdCtrl.dispose();
    _addressCtrl.dispose();
    _lengthCtrl.dispose();
    _timeoutCtrl.dispose();
    _retryCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    setState(() => _isSaving = true);
    // TODO: connect real logic — save Modbus settings to SharedPreferences
    await Future.delayed(const Duration(milliseconds: 800));
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
              const Text('Modbus settings saved'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header / toggle
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: 'tune',
                        color: theme.colorScheme.secondary,
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
                          'Modbus Settings',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Slave ID: ${_slaveIdCtrl.text} · ${_selectedFunctionCode.split(' ')[0]}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: CustomIconWidget(
                      iconName: 'keyboard_arrow_down',
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded settings form
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: _isExpanded
                ? Column(
                    children: [
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section: Connection Parameters
                            _SectionLabel(
                              label: 'Connection Parameters',
                              theme: theme,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _SettingsField(
                                    label: 'Slave ID',
                                    hint: '1–247',
                                    controller: _slaveIdCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(3),
                                    ],
                                    icon: 'tag',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SettingsField(
                                    label: 'Start Address',
                                    hint: '0x0000',
                                    controller: _addressCtrl,
                                    icon: 'pin',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _SettingsField(
                                    label: 'Register Length',
                                    hint: 'No. of registers',
                                    controller: _lengthCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(4),
                                    ],
                                    icon: 'format_list_numbered',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SettingsField(
                                    label: 'Timeout (ms)',
                                    hint: '1000',
                                    controller: _timeoutCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    icon: 'timer',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _SettingsField(
                              label: 'Retry Count',
                              hint: '3',
                              controller: _retryCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(2),
                              ],
                              icon: 'replay',
                            ),
                            const SizedBox(height: 16),

                            // Section: Protocol Parameters
                            _SectionLabel(
                              label: 'Protocol Parameters',
                              theme: theme,
                            ),
                            const SizedBox(height: 10),
                            _DropdownField(
                              label: 'Function Code',
                              value: _selectedFunctionCode,
                              items: _functionCodes,
                              icon: 'code',
                              onChanged: (v) =>
                                  setState(() => _selectedFunctionCode = v!),
                            ),
                            const SizedBox(height: 12),
                            _DropdownField(
                              label: 'Data format',
                              value: _selectedDataFormat,
                              items: kModbusDataFormatOptions,
                              icon: 'data_object',
                              itemLabel: dataFormatDisplayLabel,
                              onChanged: (v) =>
                                  setState(() => _selectedDataFormat = v!),
                            ),
                            // Byte order — disorok; default Big Endian.
                            // const SizedBox(height: 12),
                            // _DropdownField(
                            //   label: 'Byte Order',
                            //   ...
                            // ),
                            const SizedBox(height: 20),

                            // Save button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _onSave,
                                icon: _isSaving
                                    ? SizedBox(
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
                                        size: 18,
                                      ),
                                label: Text(
                                  _isSaving ? 'Saving…' : 'Save Settings',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
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
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _SectionLabel({required this.label, required this.theme});

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

class _SettingsField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String icon;

  const _SettingsField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final String icon;
  final ValueChanged<String?> onChanged;
  final String Function(String item)? itemLabel;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
    this.itemLabel,
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
            size: 18,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                itemLabel?.call(item) ?? item,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
