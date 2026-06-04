// modbus_transport.dart — Transport layer untuk Modbus (WiFi TCP + Bluetooth BLE).
//
// Diadaptasi dari rujukan loramesh/modbus_go (mekanik sambungan SAHAJA).
// TIDAK termasuk kontrak MQTT/tracking lama — publish dikendalikan PublishService.
//
// Reka bentuk:
//   - Unit pertukaran = HEX STRING (Jalan 1). Frame dibina di helper berasingan
//     (modbus_frame.dart) dari functionCode/dataType model modbusgo.
//   - ModbusTransport: kontrak unified (BT & WiFi patuh sama).
//   - WiFi: hantar hex RTU → tukar Modbus TCP (buang CRC, tambah MBAP) → socket.
//           respons → buang MBAP → hex PDU → HexResponse.
//   - BT  : hantar hex → bytes → write characteristic.
//           respons via read characteristic (notify) → hex → HexResponse.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ===================================================================
// MODEL — respons hex dari peranti
// ===================================================================

class HexResponse {
  HexResponse({
    required this.response,
    required this.timestamp,
    this.sourceCommand,
    this.isError = false,
  });

  /// Hex string PDU (untuk RTU: tanpa CRC; untuk TCP: tanpa MBAP).
  final String response;
  final DateTime timestamp;

  /// Hex command yang mencetuskan respons ini (untuk korelasi).
  final String? sourceCommand;
  final bool isError;
}

// ===================================================================
// INTERFACE — kontrak unified
// ===================================================================

abstract class ModbusTransport {
  /// Hantar hex command. Return true kalau berjaya dihantar.
  Future<bool> sendHexCommand(String hexCommand, {String description = ''});

  /// Aliran respons hex dari peranti.
  Stream<HexResponse> get hexResponseStream;

  /// Senarai semua respons diterima (sejarah).
  List<HexResponse> get receivedResponses;

  /// Status sambungan semasa.
  bool get isConnected;

  /// Aliran status sambungan — emit false bila putus (untuk maklum UI).
  Stream<bool> get connectionStateStream;

  /// Putuskan sambungan + bersihkan resource.
  Future<void> disconnect();
}

// ===================================================================
// UTIL — hex <-> bytes
// ===================================================================

Uint8List? _hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  if (clean.isEmpty || clean.length.isOdd) return null;
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < clean.length; i += 2) {
    final byte = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    out[i ~/ 2] = byte;
  }
  return out;
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return sb.toString();
}

// ===================================================================
// WIFI — Modbus TCP melalui socket
// ===================================================================

class WifiModbusTransport implements ModbusTransport {
  WifiModbusTransport();

  Socket? _socket;
  bool _connected = false;
  int _transactionId = 0;
  String? _lastSentCommand;

  final StreamController<HexResponse> _respController =
      StreamController<HexResponse>.broadcast();
  final List<HexResponse> _received = [];
  final StreamController<bool> _connController =
      StreamController<bool>.broadcast();

  @override
  Stream<HexResponse> get hexResponseStream => _respController.stream;
  @override
  List<HexResponse> get receivedResponses => List.unmodifiable(_received);
  @override
  bool get isConnected => _connected && _socket != null;
  @override
  Stream<bool> get connectionStateStream => _connController.stream;

  /// Sambung TCP ke peranti WiFi (cth EW11A). Return true kalau berjaya.
  Future<bool> connect(
    String ip,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (isConnected) return false;
    try {
      _socket = await Socket.connect(ip, port, timeout: timeout);
      _connected = true;
      _listenSocket();
      if (kDebugMode) debugPrint('✅ [WiFi] Connected $ip:$port');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [WiFi] Connect error: $e');
      _connected = false;
      _socket = null;
      return false;
    }
  }

  void _listenSocket() {
    _socket!.listen(
      (Uint8List data) {
        // Modbus TCP respons = MBAP (7 bytes) + PDU. Buang MBAP supaya
        // UI/parsing nampak PDU sahaja (selari dengan RTU).
        final pdu = data.length >= 7 ? data.sublist(7) : data;
        final resp = HexResponse(
          response: _bytesToHex(pdu),
          timestamp: DateTime.now(),
          sourceCommand: _lastSentCommand,
        );
        _received.add(resp);
        if (!_respController.isClosed) _respController.add(resp);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ [WiFi] Socket error: $e');
        _handleDisconnect();
      },
      onDone: _handleDisconnect,
      cancelOnError: false,
    );
  }

  @override
  Future<bool> sendHexCommand(String hexCommand,
      {String description = ''}) async {
    if (!isConnected) return false;
    _lastSentCommand = hexCommand;

    // hex command dianggap RTU (PDU + CRC 2 byte). Perlu sekurangnya 4 byte.
    final rtu = _hexToBytes(hexCommand);
    if (rtu == null || rtu.length < 4) return false;

    final tcpFrame = _rtuToTcp(rtu);
    try {
      _socket!.add(tcpFrame);
      await _socket!.flush();
      if (kDebugMode) debugPrint('📤 [WiFi] Sent ${tcpFrame.length} bytes');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [WiFi] Send error: $e');
      return false;
    }
  }

  /// RTU (PDU + CRC) → Modbus TCP (MBAP 7 byte + PDU, tanpa CRC).
  /// MBAP: TxID(2) ProtoID=0(2) Length(2) UnitID(1).
  Uint8List _rtuToTcp(Uint8List rtuWithCrc) {
    final pdu = rtuWithCrc.sublist(0, rtuWithCrc.length - 2); // buang CRC
    _transactionId = (_transactionId + 1) & 0xFFFF;
    final unitId = pdu.isNotEmpty ? pdu[0] : 0;
    final pduAfterUnit = pdu.length > 1 ? pdu.sublist(1) : Uint8List(0);
    final length = pduAfterUnit.length + 1; // +1 untuk unit id

    final frame = BytesBuilder();
    frame.add([(_transactionId >> 8) & 0xFF, _transactionId & 0xFF]);
    frame.add([0x00, 0x00]); // protocol id
    frame.add([(length >> 8) & 0xFF, length & 0xFF]);
    frame.add([unitId]);
    frame.add(pduAfterUnit);
    return frame.toBytes();
  }

  void _handleDisconnect() {
    final was = _connected;
    _connected = false;
    _socket = null;
    if (was && !_connController.isClosed) _connController.add(false);
  }

  @override
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _handleDisconnect();
    if (!_respController.isClosed) await _respController.close();
    if (!_connController.isClosed) await _connController.close();
  }
}

// ===================================================================
// BLUETOOTH — Modbus RTU melalui BLE GATT (UART-style)
// ===================================================================

class BleModbusTransport implements ModbusTransport {
  BleModbusTransport(this._device, this._writeChar, this._readChar);

  final BluetoothDevice _device;
  final BluetoothCharacteristic _writeChar;
  final BluetoothCharacteristic _readChar;

  bool _connected = false;
  String? _lastSentCommand;

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;

  final StreamController<HexResponse> _respController =
      StreamController<HexResponse>.broadcast();
  final List<HexResponse> _received = [];
  final StreamController<bool> _connController =
      StreamController<bool>.broadcast();

  @override
  Stream<HexResponse> get hexResponseStream => _respController.stream;
  @override
  List<HexResponse> get receivedResponses => List.unmodifiable(_received);
  @override
  bool get isConnected => _connected;
  @override
  Stream<bool> get connectionStateStream => _connController.stream;

  /// Mula dengar notify dari read characteristic. Panggil sekali selepas connect.
  Future<void> startListening() async {
    _connected = true;

    _stateSub = _device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        final was = _connected;
        _connected = false;
        if (was && !_connController.isClosed) _connController.add(false);
      }
    });

    // Aktifkan notify supaya respons masuk via onValueReceived.
    await _readChar.setNotifyValue(true);
    _notifySub = _readChar.onValueReceived.listen((data) {
      if (data.isEmpty) return;
      final resp = HexResponse(
        response: _bytesToHex(data),
        timestamp: DateTime.now(),
        sourceCommand: _lastSentCommand,
      );
      _received.add(resp);
      if (!_respController.isClosed) _respController.add(resp);
    });
  }

  @override
  Future<bool> sendHexCommand(String hexCommand,
      {String description = ''}) async {
    if (!_connected) return false;
    _lastSentCommand = hexCommand;

    final bytes = _hexToBytes(hexCommand);
    if (bytes == null) return false;

    try {
      // Selari lib rujukan: write dengan response jika disokong.
      if (_writeChar.properties.write) {
        await _writeChar.write(bytes, withoutResponse: false);
      } else if (_writeChar.properties.writeWithoutResponse) {
        await _writeChar.write(bytes, withoutResponse: true);
      } else {
        return false;
      }
      if (kDebugMode) debugPrint('📤 [BLE] Sent ${bytes.length} bytes');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] Send error: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _stateSub?.cancel();
    try {
      await _readChar.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device.disconnect();
    } catch (_) {}
    _connected = false;
    if (!_respController.isClosed) await _respController.close();
    if (!_connController.isClosed) await _connController.close();
  }
}