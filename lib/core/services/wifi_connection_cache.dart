// wifi_connection_cache.dart — Cache WifiModbusTransport aktif ikut "ip:port".
// Test-connect masa Add; guna semula masa Transmit.
import 'package:flutter/foundation.dart';
import '../transport/modbus_transport.dart';

class WifiConnectResult {
  final WifiModbusTransport? transport;
  final String? error;
  const WifiConnectResult({this.transport, this.error});
  bool get ok => transport != null;
}

class WifiConnectionCache {
  WifiConnectionCache._internal();
  static final WifiConnectionCache _instance = WifiConnectionCache._internal();
  factory WifiConnectionCache() => _instance;

  final Map<String, WifiModbusTransport> _active = {};
  String _key(String ip, int port) => '$ip:$port';

  WifiModbusTransport? activeFor(String ip, int port) {
    final t = _active[_key(ip, port)];
    if (t != null && t.isConnected) return t;
    _active.remove(_key(ip, port));
    return null;
  }

  /// Connect TCP. Cache kalau berjaya.
  Future<WifiConnectResult> connect(String ip, int port) async {
    final cached = activeFor(ip, port);
    if (cached != null) return WifiConnectResult(transport: cached);
    final t = WifiModbusTransport();
    final ok = await t.connect(ip, port);
    if (!ok) {
      return WifiConnectResult(error: 'Failed to connect to $ip:$port');
    }
    _active[_key(ip, port)] = t;
    if (kDebugMode) debugPrint('✅ [WiFi] Cached $ip:$port');
    return WifiConnectResult(transport: t);
  }
}
