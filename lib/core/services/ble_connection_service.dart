// ble_connection_service.dart — Scan → padan MAC → connect → discover → BleModbusTransport.
// Untuk projek modbusgo. Guna flutter_blue_plus 1.32.x API (tiada License param).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../transport/modbus_transport.dart';

class BleConnectResult {
  final BleModbusTransport? transport;
  final String? error;
  const BleConnectResult({this.transport, this.error});
  bool get ok => transport != null;
}

class BleConnectionService {
  BleConnectionService._internal();
  static final BleConnectionService _instance =
      BleConnectionService._internal();
  factory BleConnectionService() => _instance;

  /// Connect ikut MAC/remoteId tersimpan (device.address).
  /// Aliran teguh: scan dulu → padan id → connect → discover → bina transport.
  Future<BleConnectResult> connectByAddress(
    String address, {
    Duration scanTimeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        return const BleConnectResult(
            error: 'Bluetooth tidak disokong peranti ini');
      }
      // Pastikan adapter on.
      final adapter = await FlutterBluePlus.adapterState.first;
      if (adapter != BluetoothAdapterState.on) {
        return const BleConnectResult(error: 'Bluetooth tidak aktif');
      }

      // 1) Cuba padan dari peranti yang app dah connect (jimat scan).
      BluetoothDevice? target;
      for (final d in FlutterBluePlus.connectedDevices) {
        if (d.remoteId.str == address) {
          target = d;
          break;
        }
      }

      // 2) Kalau tiada, scan dan padan ikut remoteId.
      if (target == null) {
        final completer = Completer<BluetoothDevice?>();
        late final StreamSubscription sub;
        sub = FlutterBluePlus.onScanResults.listen((results) {
          for (final r in results) {
            if (r.device.remoteId.str == address) {
              if (!completer.isCompleted) completer.complete(r.device);
              break;
            }
          }
        });
        await FlutterBluePlus.startScan(
          timeout: scanTimeout,
          androidUsesFineLocation: true,
        );
        target = await completer.future
            .timeout(scanTimeout, onTimeout: () => null);
        await sub.cancel();
        await FlutterBluePlus.stopScan();
      }

      if (target == null) {
        return BleConnectResult(
            error: 'Peranti $address tak dijumpai semasa scan');
      }

      // 3) Connect + discover.
      await target.connect(timeout: const Duration(seconds: 20));
      final services = await target.discoverServices();

      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? readChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (writeChar == null &&
              (c.properties.write || c.properties.writeWithoutResponse)) {
            writeChar = c;
          }
          if (readChar == null && (c.properties.notify || c.properties.read)) {
            readChar = c;
          }
        }
      }

      if (writeChar == null || readChar == null) {
        await target.disconnect();
        return const BleConnectResult(
            error: 'Characteristic write/read tak dijumpai');
      }

      // 4) Bina transport core + mula dengar notify.
      final transport = BleModbusTransport(target, writeChar, readChar);
      await transport.startListening();
      if (kDebugMode) debugPrint('✅ [BLE] Transport sedia untuk $address');
      return BleConnectResult(transport: transport);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] connectByAddress: $e');
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      return BleConnectResult(error: 'Ralat sambungan: $e');
    }
  }
}
