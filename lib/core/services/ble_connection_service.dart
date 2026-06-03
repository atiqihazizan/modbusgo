// ble_connection_service.dart — Scan → pilih → connect → discover → BleModbusTransport.
// Cache transport aktif supaya skrin Transmit guna semula (elak scan 2 kali).
// flutter_blue_plus 1.32.x API (tiada License param).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../transport/modbus_transport.dart';

class BleScanItem {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  const BleScanItem(this.device, this.name, this.rssi);
  String get id => device.remoteId.str;
}

class BleConnectResult {
  final BleModbusTransport? transport;
  final String? error;
  const BleConnectResult({this.transport, this.error});
  bool get ok => transport != null;
}

class BleConnectionService {
  BleConnectionService._internal();
  static final BleConnectionService _instance = BleConnectionService._internal();
  factory BleConnectionService() => _instance;

  // Cache transport aktif ikut MAC. Transmit guna semula kalau masih connected.
  final Map<String, BleModbusTransport> _active = {};

  BleModbusTransport? activeFor(String address) {
    final t = _active[address];
    if (t != null && t.isConnected) return t;
    _active.remove(address);
    return null;
  }

  Future<bool> ensureReady() async {
    if (!await FlutterBluePlus.isSupported) return false;
    final s = await FlutterBluePlus.adapterState.first;
    return s == BluetoothAdapterState.on;
  }

  /// Scan device BLE (tapis: ada nama atau service). Pulang stream senarai terkumpul.
  Stream<List<BleScanItem>> scanBle({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    final seen = <String, BleScanItem>{};
    final controller = StreamController<List<BleScanItem>>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        // Tapis BLE: ada nama ATAU ada service UUID (buang noise tanpa identiti).
        final hasName = r.device.platformName.isNotEmpty ||
            r.advertisementData.advName.isNotEmpty;
        final hasSvc = r.advertisementData.serviceUuids.isNotEmpty;
        if (!hasName && !hasSvc) continue;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : (r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : 'BLE Device');
        seen[r.device.remoteId.str] =
            BleScanItem(r.device, name, r.rssi);
      }
      if (!controller.isClosed) {
        controller.add(seen.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi)));
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    // Pancar hasil sehingga scan tamat.
    final done = Completer<void>();
    Timer(timeout, () { if (!done.isCompleted) done.complete(); });
    yield* controller.stream;
    await done.future;
    await sub.cancel();
    await controller.close();
  }

  Future<void> stopScan() async {
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
  }

  /// Connect + discover device tertentu (dari hasil scan). Cache transport.
  Future<BleConnectResult> connectDevice(BluetoothDevice device) async {
    try {
      await stopScan();
      await device.connect(timeout: const Duration(seconds: 20));
      final services = await device.discoverServices();

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
        await device.disconnect();
        return const BleConnectResult(error: 'Characteristic write/read tak dijumpai');
      }

      final transport = BleModbusTransport(device, writeChar, readChar);
      await transport.startListening();
      _active[device.remoteId.str] = transport;
      if (kDebugMode) debugPrint('✅ [BLE] Connected ${device.remoteId.str}');
      return BleConnectResult(transport: transport);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] connectDevice: $e');
      return BleConnectResult(error: 'Ralat sambungan: $e');
    }
  }

  /// Connect ikut MAC tersimpan (untuk Transmit). Guna cache dulu, kalau tiada baru scan.
  Future<BleConnectResult> connectByAddress(
    String address, {
    Duration scanTimeout = const Duration(seconds: 8),
  }) async {
    final cached = activeFor(address);
    if (cached != null) return BleConnectResult(transport: cached);

    if (!await ensureReady()) {
      return const BleConnectResult(error: 'Bluetooth tidak aktif/disokong');
    }
    // Cuba dari peranti yang app dah connect.
    for (final d in FlutterBluePlus.connectedDevices) {
      if (d.remoteId.str == address) return connectDevice(d);
    }
    // Scan & padan remoteId.
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
        timeout: scanTimeout, androidUsesFineLocation: true);
    final target =
        await completer.future.timeout(scanTimeout, onTimeout: () => null);
    await sub.cancel();
    await stopScan();
    if (target == null) {
      return BleConnectResult(error: 'Peranti $address tak dijumpai');
    }
    return connectDevice(target);
  }
}
