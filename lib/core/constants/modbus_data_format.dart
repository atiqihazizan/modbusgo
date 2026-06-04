// Label UI "Data format" — disimpan dalam ModbusDevice.dataType (lowercase).
// Decode dalaman kekal dalam modbus_frame.dart (ModbusDataType).

const String kDefaultModbusByteOrder = 'Big Endian';

/// Pilihan dropdown UI.
const List<String> kModbusDataFormatOptions = [
  'decimal',
  'hexadecimal',
  'float',
  'binary',
];

const _displayLabels = <String, String>{
  'decimal': 'Decimal',
  'hexadecimal': 'Hexadecimal',
  'float': 'Float',
  'binary': 'Binary',
};

/// Normalkan input (UI, legacy INT16 / signed, dll.) → format disimpan.
String normalizeDataFormat(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return 'decimal';

  final lower = s.toLowerCase();
  if (kModbusDataFormatOptions.contains(lower)) return lower;

  switch (lower) {
    case 'signed':
    case 'unsigned':
    case 'long':
    case 'double':
      return 'decimal';
    case 'hex':
      return 'hexadecimal';
    default:
      break;
  }

  switch (s.toUpperCase()) {
    case 'INT16':
    case 'INT32':
    case 'UINT16':
    case 'UINT32':
    case 'FLOAT64':
      return 'decimal';
    case 'FLOAT32':
      return 'float';
    case 'BOOL':
      return 'binary';
    case 'STRING':
      return 'decimal';
    default:
      return 'decimal';
  }
}

String dataFormatDisplayLabel(String stored) {
  final n = normalizeDataFormat(stored);
  return _displayLabels[n] ?? 'Decimal';
}

int defaultRegisterCountForDataFormat(String format) {
  switch (normalizeDataFormat(format)) {
    case 'float':
      return 2;
    case 'decimal':
    case 'hexadecimal':
    case 'binary':
    default:
      return 1;
  }
}

/// Paparan nilai decode ikut format UI (MQTT/publish kekal nombor).
String formatRegisterValueForDisplay(num value, String dataFormat) {
  switch (normalizeDataFormat(dataFormat)) {
    case 'hexadecimal':
      final iv = value is int ? value : value.round();
      return '0x${(iv & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}';
    case 'binary':
      final iv = value is int ? value : value.round();
      return (iv & 0xFFFF).toRadixString(2).padLeft(16, '0');
    case 'float':
      return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    case 'decimal':
    default:
      return value.toString();
  }
}
