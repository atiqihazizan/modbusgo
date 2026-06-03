// ble_connection_service.dart — Scan → pilih → connect → discover → BleModbusTransport.
// Cache transport aktif supaya skrin Transmit guna semula (elak scan 2 kali).
// flutter_blue_plus 1.32.x API (tiada License param).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../transport/modbus_transport.dart';

class BleScanItem {
  final BluetoothDevice device;
  /// Nama paparan untuk user (bukan semestinya = MAC).
  final String label;
  /// Alamat MAC / remoteId (satu baris).
  final String mac;
  /// Petunjuk servis BLE atau jenis peranti.
  final String hint;
  final int rssi;
  const BleScanItem({
    required this.device,
    required this.label,
    required this.mac,
    required this.hint,
    required this.rssi,
  });
  String get id => mac.isNotEmpty ? mac : _tryRemoteId(device);
  /// Alias lama — label paparan.
  String get name => label;

  static String _tryRemoteId(BluetoothDevice device) {
    try {
      final s = device.remoteId.str;
      return s.isEmpty ? '' : s.toUpperCase();
    } catch (_) {
      return '';
    }
  }
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

  /// Kunci cache seragam (elak mismatch huruf besar/kecil).
  static String normBleAddress(String address) =>
      address.trim().toUpperCase();

  BleModbusTransport? activeFor(String address) {
    final k = normBleAddress(address);
    final t = _active[k];
    if (t != null && t.isConnected) return t;
    _active.remove(k);
    return null;
  }

  Future<bool> ensureReady() async {
    if (!await FlutterBluePlus.isSupported) return false;
    var state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      state = await FlutterBluePlus.adapterState.first;
    }
    return state == BluetoothAdapterState.on;
  }

  static final RegExp _macPattern =
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  /// Tapis iklan BLE connectable (bukan beacon/passive sahaja).
  static bool isConnectableBle(ScanResult r) =>
      r.advertisementData.connectable;

  static String _serviceHint(AdvertisementData ad) {
    for (final g in ad.serviceUuids) {
      final s = g.toString().toLowerCase();
      if (s.contains('6e400001')) return 'Nordic UART · sesuai Modbus BLE';
      if (s.contains('ffe0') || s.contains('ff00')) {
        return 'Serial BLE · kemungkinan Modbus';
      }
    }
    if (ad.serviceUuids.isNotEmpty) {
      return 'BLE · ${ad.serviceUuids.length} servis GATT';
    }
    return 'BLE · boleh disambung';
  }

  static String _displayLabel(ScanResult r, int listIndex) {
    final platform = r.device.platformName.trim();
    final adv = r.advertisementData.advName.trim();
    if (platform.isNotEmpty && !_macPattern.hasMatch(platform)) {
      return platform;
    }
    if (adv.isNotEmpty && !_macPattern.hasMatch(adv)) {
      return adv;
    }
    return 'Peranti BLE #$listIndex';
  }

  static String _macFromScanResult(ScanResult r) {
    try {
      final s = r.device.remoteId.str;
      if (s.isNotEmpty) return s.toUpperCase();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [BLE] remoteId invalid, skip: $e');
    }
    return '';
  }

  static BleScanItem? tryFromScanResult(ScanResult r, {required int listIndex}) {
    final mac = _macFromScanResult(r);
    if (mac.isEmpty) return null;
    return BleScanItem(
      device: r.device,
      label: _displayLabel(r, listIndex),
      mac: mac,
      hint: _serviceHint(r.advertisementData),
      rssi: r.rssi,
    );
  }

  static BleScanItem fromScanResult(ScanResult r, {required int listIndex}) {
    final item = tryFromScanResult(r, listIndex: listIndex);
    assert(item != null, 'fromScanResult: MAC invalid');
    return item!;
  }

  static List<BleScanItem> mapScanResults(List<ScanResult> results) {
    final filtered =
        results.where(isConnectableBle).toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final out = <BleScanItem>[];
    for (final r in filtered) {
      final item = tryFromScanResult(r, listIndex: out.length + 1);
      if (item != null) out.add(item);
    }
    return out;
  }

  int _scanGeneration = 0;

  /// Satu imbasan pada satu masa (elak start/stop bertindih → status=6 Android).
  Future<void> startDeviceScan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final gen = ++_scanGeneration;
    await stopScan();
    // Beri masa scanner Android reset selepas stopScan.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (gen != _scanGeneration) return;

    try {
      if (kDebugMode) debugPrint('🔵 [BLE] startDeviceScan (gen=$gen)');
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      if (kDebugMode) debugPrint('🔵 [BLE] scan tamat (gen=$gen)');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] startScan: $e');
      rethrow;
    }
  }

  /// Batalkan imbasan / sesi semasa (dialog ditutup atau refresh).
  Future<void> cancelScanSession() async {
    _scanGeneration++;
    await stopScan();
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
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
        return const BleConnectResult(
            error: 'Characteristic write/read tak dijumpai');
      }

      final transport = BleModbusTransport(device, writeChar, readChar);
      await transport.startListening();
      _active[normBleAddress(device.remoteId.str)] = transport;
      if (kDebugMode) {
        debugPrint('✅ [BLE] Connected ${normBleAddress(device.remoteId.str)}');
      }
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
    final want = normBleAddress(address);
    // Cuba dari peranti yang app dah connect.
    for (final d in FlutterBluePlus.connectedDevices) {
      if (normBleAddress(d.remoteId.str) == want) return connectDevice(d);
    }
    // Scan & padan remoteId.
    final completer = Completer<BluetoothDevice?>();
    late final StreamSubscription sub;
    sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (normBleAddress(r.device.remoteId.str) == want) {
          if (!completer.isCompleted) completer.complete(r.device);
          break;
        }
      }
    });
    try {
      await stopScan();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await FlutterBluePlus.startScan(
        timeout: scanTimeout,
        androidUsesFineLocation: false,
      );
      final target = await completer.future.timeout(
        scanTimeout,
        onTimeout: () => null,
      );
      if (target == null) {
        return BleConnectResult(error: 'Peranti $address tak dijumpai');
      }
      return connectDevice(target);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] connectByAddress scan: $e');
      return BleConnectResult(error: 'Scan gagal: $e');
    } finally {
      await sub.cancel();
      await stopScan();
    }
  }
}
