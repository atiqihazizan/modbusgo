// modbus_frame.dart — Helper bina hex command + parse respons.
//
// Asingkan dari transport (Jalan 1): UI/poll panggil helper untuk dapatkan hex
// RTU, kemudian hantar ke ModbusTransport.sendHexCommand().
//
// UI modbusgo guna String ("FC03", "INT16") — helper terjemah ke int/format.
// CRC16 + frame builder diadaptasi dari rujukan ModbusTransmission.generateCommand().
//
// Output hex = format RTU: [slaveId][FC][...payload][CRC_lo][CRC_hi]
//   - WiFi transport akan tukar RTU→TCP (buang CRC, tambah MBAP) sendiri.
//   - BLE transport hantar RTU apa adanya.

import 'dart:typed_data';

// ===================================================================
// PEMETA String (UI) → int / enum
// ===================================================================

/// "FC03" / "FC3" / "3" → 3. Throw kalau tak sah.
int functionCodeToInt(String fc) {
  final cleaned = fc.toUpperCase().replaceAll('FC', '').trim();
  final v = int.tryParse(cleaned);
  if (v == null) throw ArgumentError('Function code tak sah: $fc');
  return v;
}

enum ModbusDataType { int16, uint16, int32, uint32, float32, float64, boolType }

ModbusDataType dataTypeFromString(String s) {
  switch (s.toUpperCase()) {
    case 'INT16':
      return ModbusDataType.int16;
    case 'UINT16':
      return ModbusDataType.uint16;
    case 'INT32':
      return ModbusDataType.int32;
    case 'UINT32':
      return ModbusDataType.uint32;
    case 'FLOAT32':
      return ModbusDataType.float32;
    case 'FLOAT64':
      return ModbusDataType.float64;
    case 'BOOL':
      return ModbusDataType.boolType;
    default:
      return ModbusDataType.int16;
  }
}

enum ModbusByteOrder { bigEndian, littleEndian, bigEndianSwap, littleEndianSwap }

ModbusByteOrder byteOrderFromString(String s) {
  switch (s.toLowerCase()) {
    case 'little endian':
      return ModbusByteOrder.littleEndian;
    case 'big endian swap':
      return ModbusByteOrder.bigEndianSwap;
    case 'little endian swap':
      return ModbusByteOrder.littleEndianSwap;
    case 'big endian':
    default:
      return ModbusByteOrder.bigEndian;
  }
}

// ===================================================================
// CRC16 (Modbus) — algoritma standard, port dari rujukan
// ===================================================================

/// Kira CRC16-Modbus untuk senarai byte. Return [lo, hi] (urutan RTU).
List<int> _crc16(List<int> bytes) {
  var crc = 0xFFFF;
  for (final b in bytes) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x0001) != 0) {
        crc >>= 1;
        crc ^= 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  // RTU hantar low byte dulu.
  return [crc & 0xFF, (crc >> 8) & 0xFF];
}

String _hex2(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

// ===================================================================
// BINA FRAME (hex RTU) untuk operasi READ (FC 1-4)
// ===================================================================

/// Bina hex command RTU untuk read (FC01/02/03/04).
/// [slaveId] 1-247, [functionCode] 1-4, [startAddress] 0-65535,
/// [registerCount] 1-125. Return hex string tanpa ruang (cth "010300000002C40B").
String buildReadCommand({
  required int slaveId,
  required int functionCode,
  required int startAddress,
  required int registerCount,
}) {
  if (functionCode < 1 || functionCode > 4) {
    throw ArgumentError('buildReadCommand hanya untuk FC01-04, dapat $functionCode');
  }
  final frame = <int>[
    slaveId & 0xFF,
    functionCode & 0xFF,
    (startAddress >> 8) & 0xFF,
    startAddress & 0xFF,
    (registerCount >> 8) & 0xFF,
    registerCount & 0xFF,
  ];
  final crc = _crc16(frame);
  final all = [...frame, ...crc];
  return all.map(_hex2).join();
}

/// Bina hex command dari pilihan UI (String). Lapisan nyaman untuk skrin.
String buildReadCommandFromUi({
  required int slaveId,
  required String functionCode, // "FC03"
  required int startAddress,
  required int registerCount,
}) {
  return buildReadCommand(
    slaveId: slaveId,
    functionCode: functionCodeToInt(functionCode),
    startAddress: startAddress,
    registerCount: registerCount,
  );
}

// ===================================================================
// PARSE RESPONS — hex PDU → senarai nilai register
// ===================================================================

/// Ekstrak nilai register 16-bit mentah dari respons hex.
/// Respons boleh PDU ([FC, byteCount, data...]) atau RTU ([slave, FC, byteCount, data...]).
/// Diadaptasi dari rujukan _extractRegisterValuesManual (auto-detect byte count index).
/// Respons Modbus exception: function code dengan bit 0x80 (PDU atau RTU).
bool isModbusExceptionResponse(String responseHex) {
  final clean = responseHex.replaceAll(RegExp(r'\s+'), '');
  if (clean.length < 4 || clean.length.isOdd) return false;
  final bytes = <int>[];
  for (var i = 0; i < clean.length; i += 2) {
    final b = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (b == null) return false;
    bytes.add(b);
  }
  if (bytes.length < 2) return false;
  // PDU: [unit/FC][FC] — cuba index 1, kemudian index 2 (RTU dengan slave).
  if ((bytes[1] & 0x80) != 0) return true;
  if (bytes.length >= 3 && (bytes[2] & 0x80) != 0) return true;
  return false;
}

List<int> extractRawRegisters(String responseHex) {
  final clean = responseHex.replaceAll(RegExp(r'\s+'), '');
  if (clean.length < 6 || clean.length.isOdd) return [];

  // Pecah jadi byte.
  final bytes = <int>[];
  for (var i = 0; i < clean.length; i += 2) {
    final b = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (b == null) return [];
    bytes.add(b);
  }

  // Cari index byteCount: cuba index 1 (PDU), fallback index 2 (RTU dengan slave).
  int bcIndex = -1;
  int byteCount = 0;
  if (bytes.length > 2) {
    final c = bytes[1];
    if (c > 0 && c <= 250 && c.isEven) {
      bcIndex = 1;
      byteCount = c;
    }
  }
  if (bcIndex == -1 && bytes.length > 3) {
    final c = bytes[2];
    if (c > 0 && c < 256) {
      bcIndex = 2;
      byteCount = c;
    }
  }
  if (bcIndex == -1) return [];

  final dataStart = bcIndex + 1;
  final dataEnd = dataStart + byteCount;
  if (bytes.length < dataEnd) return [];

  final data = bytes.sublist(dataStart, dataEnd);
  final regs = <int>[];
  for (var i = 0; i + 1 < data.length; i += 2) {
    regs.add((data[i] << 8) | data[i + 1]); // big endian register
  }
  return regs;
}

/// Tukar register mentah → nilai ikut dataType + byteOrder.
/// Pulang List<num> sedia untuk publish (sensor_data).
/// Nota: ini liputan asas (INT16/UINT16/INT32/UINT32/FLOAT32). FLOAT64 perlu 4 reg.
List<num> decodeRegisters(
  List<int> raw, {
  required ModbusDataType dataType,
  required ModbusByteOrder byteOrder,
}) {
  if (raw.isEmpty) return [];

  switch (dataType) {
    case ModbusDataType.int16:
      return raw.map((r) => _toSigned16(r)).toList();
    case ModbusDataType.uint16:
    case ModbusDataType.boolType:
      return raw;
    case ModbusDataType.int32:
    case ModbusDataType.uint32:
    case ModbusDataType.float32:
      return _decode32(raw, dataType, byteOrder);
    case ModbusDataType.float64:
      // 4 register setiap nilai — liputan minimum, pulang mentah kalau tak cukup.
      return raw;
  }
}

int _toSigned16(int v) => v >= 0x8000 ? v - 0x10000 : v;

List<num> _decode32(
  List<int> raw,
  ModbusDataType type,
  ModbusByteOrder order,
) {
  final out = <num>[];
  for (var i = 0; i + 1 < raw.length; i += 2) {
    final hi = raw[i];
    final lo = raw[i + 1];

    // Susun perkataan ikut byte order (word swap untuk *Swap).
    int combined;
    switch (order) {
      case ModbusByteOrder.bigEndian:
      case ModbusByteOrder.littleEndian:
        combined = (hi << 16) | lo;
        break;
      case ModbusByteOrder.bigEndianSwap:
      case ModbusByteOrder.littleEndianSwap:
        combined = (lo << 16) | hi;
        break;
    }
    combined &= 0xFFFFFFFF;

    if (type == ModbusDataType.float32) {
      final bd = ByteData(4)..setUint32(0, combined);
      out.add(bd.getFloat32(0));
    } else if (type == ModbusDataType.int32) {
      out.add(combined >= 0x80000000 ? combined - 0x100000000 : combined);
    } else {
      out.add(combined); // uint32
    }
  }
  return out;
}