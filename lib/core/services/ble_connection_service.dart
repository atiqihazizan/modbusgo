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
      if (s.contains('6e400001')) return 'Nordic UART · suitable for Modbus BLE';
      if (s.contains('ffe0') || s.contains('ff00')) {
        return 'Serial BLE · possible Modbus';
      }
    }
    if (ad.serviceUuids.isNotEmpty) {
      return 'BLE · ${ad.serviceUuids.length} GATT services';
    }
    return 'BLE · connectable';
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
    return 'BLE device #$listIndex';
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
      if (kDebugMode) debugPrint('🔵 [BLE] scan finished (gen=$gen)');
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

  static bool _uuidContains(String uuid, String fragment) {
    final u = uuid.toLowerCase().replaceAll('-', '');
    final f = fragment.toLowerCase().replaceAll('-', '');
    return u.contains(f);
  }

  /// Skor write char — utamakan Nordic UART RX / serial BLE (selari lib lama).
  static int _writeCharScore(BluetoothCharacteristic c) {
    if (!c.properties.write && !c.properties.writeWithoutResponse) return 0;
    final u = c.uuid.toString();
    if (_uuidContains(u, '6e400002')) return 100;
    if (_uuidContains(u, 'ffe0') || _uuidContains(u, 'fff2')) return 90;
    return c.properties.write ? 60 : 50;
  }

  /// Skor notify/read — utamakan notify + UUID TX serial (elak char read generik GAP).
  static int _notifyCharScore(BluetoothCharacteristic c) {
    final u = c.uuid.toString();
    if (c.properties.notify) {
      if (_uuidContains(u, '6e400003')) return 100;
      if (_uuidContains(u, 'ffe1') || _uuidContains(u, 'fff1')) return 90;
      return 70;
    }
    if (c.properties.indicate) return 40;
    if (c.properties.read) return 5;
    return 0;
  }

  static ({BluetoothCharacteristic? write, BluetoothCharacteristic? notify})
      pickModbusCharacteristics(List<BluetoothService> services) {
    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? notifyChar;
    var bestWrite = 0;
    var bestNotify = 0;

    for (final s in services) {
      for (final c in s.characteristics) {
        final ws = _writeCharScore(c);
        if (ws > bestWrite) {
          bestWrite = ws;
          writeChar = c;
        }
        final ns = _notifyCharScore(c);
        if (ns > bestNotify) {
          bestNotify = ns;
          notifyChar = c;
        }
      }
    }

    // Fallback seperti lib: char write/notify terakhir jika tiada skor tinggi.
    if (writeChar == null || notifyChar == null || bestNotify < 10) {
      BluetoothCharacteristic? lastWrite;
      BluetoothCharacteristic? lastNotify;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            lastWrite = c;
          }
          if (c.properties.notify || c.properties.indicate) {
            lastNotify = c;
          }
        }
      }
      writeChar ??= lastWrite;
      notifyChar ??= lastNotify;
    }

    return (write: writeChar, notify: notifyChar);
  }

  /// Connect + discover device tertentu (dari hasil scan). Cache transport.
  Future<BleConnectResult> connectDevice(BluetoothDevice device) async {
    try {
      await stopScan();
      await device.connect(timeout: const Duration(seconds: 20));
      final services = await device.discoverServices();

      final picked = pickModbusCharacteristics(services);
      final writeChar = picked.write;
      final readChar = picked.notify;
      if (writeChar == null || readChar == null) {
        await device.disconnect();
        return const BleConnectResult(
            error: 'Write/read characteristic not found');
      }

      final transport = BleModbusTransport(device, writeChar, readChar);
      await transport.startListening();
      _active[normBleAddress(device.remoteId.str)] = transport;
      if (kDebugMode) {
        debugPrint(
          '✅ [BLE] Connected ${normBleAddress(device.remoteId.str)} '
          'write=${writeChar.uuid} notify=${readChar.uuid}',
        );
      }
      return BleConnectResult(transport: transport);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] connectDevice: $e');
      return BleConnectResult(error: 'Connection error: $e');
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
      return const BleConnectResult(error: 'Bluetooth is off or not supported');
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
        return BleConnectResult(error: 'Device $address not found');
      }
      return connectDevice(target);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BLE] connectByAddress scan: $e');
      return BleConnectResult(error: 'Scan failed: $e');
    } finally {
      await sub.cancel();
      await stopScan();
    }
  }
}
