import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../core/services/ble_connection_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/modbus_storage_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/publish_service.dart';
import '../../core/services/wifi_connection_cache.dart';
import '../../core/transport/modbus_frame.dart';
import '../../core/transport/modbus_transport.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/custom_icon_widget.dart';
import '../home_screen/widgets/modbus_device_panel_widget.dart';
import '../home_screen/widgets/modbus_settings_widget.dart';

// ─── Model: Satu entri dalam log TX/RX ───────────────────────────────────────
class TxRxLogEntry {
  final bool isTx; // true = hantar (TX), false = terima (RX)
  final String data; // hex string atau data mentah
  final DateTime time;
  final bool isError; // papar merah jika ada ralat

  const TxRxLogEntry({
    required this.isTx,
    required this.data,
    required this.time,
    this.isError = false,
  });
}

// ─── Screen Utama ─────────────────────────────────────────────────────────────
class ModbusTransmissionScreen extends StatefulWidget {
  final ModbusDevice device;

  const ModbusTransmissionScreen({super.key, required this.device});

  @override
  State<ModbusTransmissionScreen> createState() =>
      _ModbusTransmissionScreenState();
}

class _ModbusTransmissionScreenState extends State<ModbusTransmissionScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool isConnected = false; // status sambungan ke device
  bool isLooping = false; // adakah polling loop sedang berjalan
  String commandText = ''; // arahan hex yang dijana
  String? lastResponse; // respons terakhir dari device
  List<TxRxLogEntry> txRxLog = []; // senarai log TX/RX, terbaru di atas
  List<num> registerValues = []; // nilai register yang didekod

  late TabController _tabController;

  ModbusTransport? _transport; // transport aktif (BLE buat masa ni)
  StreamSubscription<HexResponse>? _rxSub;
  StreamSubscription<bool>? _connSub;
  Timer? _nextPollTimer;
  Timer? _rxTimeoutTimer;
  bool _awaitingRx = false; // TX dalam flight — tunggu RX/timeout sebelum poll seterusnya
  late ModbusDevice _device; // salinan boleh-ubah (boleh ditukar selepas edit)
  Duration _pollInterval = const Duration(milliseconds: 1000);
  Duration _responseTimeout = const Duration(milliseconds: 1000); // global, dimuat async
  String _sendableCommand = ''; // hex RTU sebenar (ada CRC) untuk dihantar

  Future<void> _loadGlobalRxTimeout() async {
    final ms = await LocalStorageService().getModbusRxTimeoutMs();
    if (!mounted) return;
    setState(() => _responseTimeout = Duration(milliseconds: ms));
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _pollInterval = Duration(milliseconds: _device.pollInterval);
    _tabController = TabController(length: 2, vsync: this);
    _loadGlobalRxTimeout(); // isi _responseTimeout dari tetapan global
    PublishService().pauseGps(); // Modbus pegang kawalan publish
    LocationService().start(); // pastikan lastFix sentiasa segar untuk publishModbus
    _rebuildCommand(); // jana commandText + _sendableCommand + registerValues
    // Auto-connect bila masuk skrin (BLE sahaja buat masa ni).
    WidgetsBinding.instance.addPostFrameCallback((_) => onConnect());
  }

  @override
  void dispose() {
    _nextPollTimer?.cancel();
    _rxTimeoutTimer?.cancel();
    _awaitingRx = false;
    _rxSub?.cancel();
    _connSub?.cancel();
    _transport?.disconnect();
    PublishService().resumeGps(); // sambung semula GPS publish
    _tabController.dispose();
    super.dispose();
  }

  // ── Helper: Jana arahan Modbus RTU hex ────────────────────────────────────
  String _buildHexCommand(ModbusDevice device) {
    // Contoh: FC03 → Read Holding Registers
    // Format: [SlaveID][FC][AddrHi][AddrLo][CountHi][CountLo][CRC_placeholder]
    final slaveHex = device.slaveId
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final fcMap = {
      'FC01': '01',
      'FC02': '02',
      'FC03': '03',
      'FC04': '04',
      'FC05': '05',
      'FC06': '06',
    };
    final fc = fcMap[device.functionCode] ?? '03';
    final addrHi = (device.startAddress >> 8)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final addrLo = (device.startAddress & 0xFF)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final cntHi = (device.registerCount >> 8)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final cntLo = (device.registerCount & 0xFF)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return '$slaveHex $fc $addrHi$addrLo $cntHi$cntLo [CRC]';
  }

  /// Jana semula arahan + senarai register dari _device semasa.
  void _rebuildCommand() {
    commandText = _buildHexCommand(_device);
    try {
      _sendableCommand = buildReadCommandFromUi(
        slaveId: _device.slaveId,
        functionCode: _device.functionCode,
        startAddress: _device.startAddress,
        registerCount: _device.registerCount,
      );
    } catch (_) {
      _sendableCommand = '';
    }
    registerValues = List.filled(_device.registerCount, 0);
  }

  // ── Format masa untuk log ──────────────────────────────────────────────────
  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────────────────
  // CALLBACK HOOKS — sambung ke servis transport kemudian
  // ─────────────────────────────────────────────────────────────────────────

  ({String ip, int port})? _parseWifiEndpoint(String address) {
    final i = address.lastIndexOf(':');
    if (i <= 0) return null;
    final ip = address.substring(0, i);
    final port = int.tryParse(address.substring(i + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return (ip: ip, port: port);
  }

  Future<void> onConnect() async {
    if (widget.device.connectionType == ModbusConnectionType.bluetooth) {
      final result = await BleConnectionService()
          .connectByAddress(widget.device.address);
      if (!mounted) return;
      if (!result.ok) {
        setState(() => isConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Sambungan gagal')),
        );
        return;
      }
      _transport = result.transport;
    } else {
      final ep = _parseWifiEndpoint(widget.device.address);
      if (ep == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Format address WiFi tidak sah (ip:port)')),
        );
        return;
      }
      final result =
          await WifiConnectionCache().connect(ep.ip, ep.port);
      if (!mounted) return;
      if (!result.ok) {
        setState(() => isConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Sambungan gagal')),
        );
        return;
      }
      _transport = result.transport;
    }
    _rxSub = _transport!.hexResponseStream.listen(_onRxResponse);
    _connSub?.cancel();
    _connSub = _transport!.connectionStateStream.listen((connected) {
      if (!connected) _handleTransportLost();
    });
    setState(() => isConnected = true);
  }

  /// Dipanggil bila transport putus di tengah sesi (cabut kuasa, keluar julat).
  void _handleTransportLost() {
    if (!mounted) return;
    _nextPollTimer?.cancel();
    _rxTimeoutTimer?.cancel();
    _awaitingRx = false;
    setState(() {
      isConnected = false;
      isLooping = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sambungan terputus. Tekan reconnect untuk cuba semula.'),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  /// Reconnect manual — bersihkan transport lama, cuba sambung semula.
  Future<void> _reconnect() async {
    _connSub?.cancel();
    _rxSub?.cancel();
    _transport = null;
    await onConnect();
  }

  void onDisconnect() {
    _nextPollTimer?.cancel();
    _rxTimeoutTimer?.cancel();
    _awaitingRx = false;
    _rxSub?.cancel();
    _connSub?.cancel();
    _transport?.disconnect();
    _transport = null;
    if (mounted) {
      setState(() {
        isConnected = false;
        isLooping = false;
      });
    }
  }

  void onStartLoop() {
    if (_transport == null || _sendableCommand.isEmpty) return;
    _nextPollTimer?.cancel();
    _rxTimeoutTimer?.cancel();
    _awaitingRx = false;
    setState(() => isLooping = true);
    _kickPollCycle();
  }

  void onStopLoop() {
    _nextPollTimer?.cancel();
    _nextPollTimer = null;
    _rxTimeoutTimer?.cancel();
    _rxTimeoutTimer = null;
    _awaitingRx = false;
    if (mounted) setState(() => isLooping = false);
  }

  /// Mulakan satu kitaran poll (satu TX) jika tiada permintaan sedang menunggu RX.
  void _kickPollCycle() {
    if (!isLooping || _transport == null || _sendableCommand.isEmpty) return;
    if (_awaitingRx) return;
    _sendPollRequest();
  }

  void _scheduleNextPollCycle() {
    if (!isLooping || !mounted) return;
    _nextPollTimer?.cancel();
    _nextPollTimer = Timer(_pollInterval, () {
      if (mounted && isLooping) _kickPollCycle();
    });
  }

  Future<void> _sendPollRequest() async {
    final t = _transport;
    if (t == null || !isLooping) return;
    if (_awaitingRx) return;

    final ok = await t.sendHexCommand(_sendableCommand);
    if (!mounted || !isLooping) return;

    setState(() {
      txRxLog.insert(
        0,
        TxRxLogEntry(
          isTx: true,
          data: _sendableCommand,
          time: DateTime.now(),
          isError: !ok,
        ),
      );
    });

    if (!ok) {
      _finishPollCycle(
        HexResponse(
          response: 'TX_FAIL',
          timestamp: DateTime.now(),
          sourceCommand: _sendableCommand,
          isError: true,
        ),
      );
      return;
    }

    _awaitingRx = true;
    _rxTimeoutTimer?.cancel();
    _rxTimeoutTimer = Timer(_responseTimeout, () {
      if (!mounted || !isLooping || !_awaitingRx) return;
      _finishPollCycle(
        HexResponse(
          response: 'TIMEOUT',
          timestamp: DateTime.now(),
          sourceCommand: _sendableCommand,
          isError: true,
        ),
      );
    });
  }

  HexResponse _normalizeResponse(HexResponse resp) {
    if (resp.isError) return resp;
    if (isModbusExceptionResponse(resp.response)) {
      return HexResponse(
        response: resp.response,
        timestamp: resp.timestamp,
        sourceCommand: resp.sourceCommand,
        isError: true,
      );
    }
    return resp;
  }

  void _finishPollCycle(HexResponse resp) {
    _rxTimeoutTimer?.cancel();
    _awaitingRx = false;
    _applyRxToUi(_normalizeResponse(resp));
    if (isLooping && mounted) _scheduleNextPollCycle();
  }

  void _onRxResponse(HexResponse resp) {
    if (!mounted) return;
    final normalized = _normalizeResponse(resp);
    if (isLooping) {
      if (!_awaitingRx) return;
      _finishPollCycle(normalized);
      return;
    }
    _applyRxToUi(normalized);
  }

  void _applyRxToUi(HexResponse resp) {
    final txType = widget.device.connectionType == ModbusConnectionType.bluetooth
        ? 'Bluetooth'
        : 'WiFi';
    final synthetic = resp.response == 'TIMEOUT' || resp.response == 'TX_FAIL';
    List<num> decoded = [];
    if (!synthetic && !resp.isError) {
      final raw = extractRawRegisters(resp.response);
      decoded = decodeRegisters(
        raw,
        dataType: dataTypeFromString(widget.device.dataType),
        byteOrder: byteOrderFromString(widget.device.byteOrder),
      );
    }

    setState(() {
      if (!synthetic) lastResponse = resp.response;
      if (!resp.isError && decoded.isNotEmpty) registerValues = decoded;
      txRxLog.insert(
        0,
        TxRxLogEntry(
          isTx: false,
          data: resp.response,
          time: DateTime.now(),
          isError: resp.isError,
        ),
      );
    });

    List<dynamic> sensorPayload;
    if (resp.response == 'TIMEOUT') {
      sensorPayload = const ['TMO'];
    } else if (resp.isError) {
      sensorPayload = const ['ERR'];
    } else {
      sensorPayload = decoded.isNotEmpty ? decoded : [-1];
    }
    PublishService().publishModbus(
      sensorData: sensorPayload,
      transmissionType: txType,
    );
  }

  Future<void> onOpenSettings() async {
    final result = await showModbusEditDialog(context, _device);
    if (result == null || !mounted) return;
    final updated = _device.copyWith(
      name: result['name'] as String,
      slaveId: result['slaveId'] as int,
      functionCode: result['functionCode'] as String,
      dataType: result['dataType'] as String,
      byteOrder: result['byteOrder'] as String,
      startAddress: result['startAddress'] as int,
      registerCount: result['registerCount'] as int,
      pollInterval: result['pollInterval'] as int? ?? _device.pollInterval,
    );
    await ModbusStorageService().update(updated);
    if (!mounted) return;

    final wasLooping = isLooping;
    if (wasLooping) onStopLoop(); // henti guna command lama

    setState(() {
      _device = updated;
      _pollInterval = Duration(milliseconds: updated.pollInterval);
      _rebuildCommand();
    });

    if (wasLooping) onStartLoop(); // mula semula guna nilai baharu

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tetapan dikemas kini.')),
    );
  }

  // ── Toggle polling loop ────────────────────────────────────────────────────
  void _toggleLoop() {
    if (isLooping) {
      onStopLoop();
    } else {
      onStartLoop();
    }
  }

  // ── Salin teks ke clipboard ────────────────────────────────────────────────
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Disalin ke clipboard'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme, colorScheme),
      body: Column(
        children: [
          // ── Header card: maklumat device + arahan hex ──────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(4.w, 1.5.h, 4.w, 0),
            child: _buildHeaderCard(theme, colorScheme),
          ),
          SizedBox(height: 1.5.h),
          // ── TabBar ─────────────────────────────────────────────────────
          _buildTabBar(theme, colorScheme),
          // ── Tab content ────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTxRxLogTab(theme, colorScheme),
                _buildRegisterValuesTab(theme, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(ThemeData theme, ColorScheme colorScheme) {
    return AppBar(
      title: Text(
        'Transmission',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 18.sp > 20 ? 20 : 18.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        // Dot status sambungan
        Padding(
          padding: EdgeInsets.only(right: 1.w),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? AppTheme.success : AppTheme.errorColor,
                boxShadow: [
                  BoxShadow(
                    color:
                        (isConnected ? AppTheme.success : AppTheme.errorColor)
                            .withAlpha(100),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Butang reconnect — muncul bila terputus
        if (!isConnected)
          IconButton(
            icon: const CustomIconWidget(
              iconName: 'refresh',
              size: 22,
              color: AppTheme.errorColor,
            ),
            tooltip: 'Sambung semula',
            onPressed: _reconnect,
          ),
        // Butang tetapan Modbus
        IconButton(
          icon: const CustomIconWidget(iconName: 'settings', size: 22),
          tooltip: 'Tetapan Modbus',
          onPressed: onOpenSettings,
        ),
        // Butang Send/Stop toggle
        Padding(
          padding: EdgeInsets.only(right: 2.w),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isLooping
                  ? const CustomIconWidget(
                      key: ValueKey('stop'),
                      iconName: 'stop_circle',
                      size: 24,
                      color: AppTheme.errorColor,
                    )
                  : CustomIconWidget(
                      key: const ValueKey('send'),
                      iconName: 'send',
                      size: 22,
                      color: colorScheme.primary,
                    ),
            ),
            tooltip: isLooping ? 'Hentikan polling' : 'Mula polling',
            onPressed: _toggleLoop,
          ),
        ),
      ],
    );
  }

  // ── Header Card ────────────────────────────────────────────────────────────
  Widget _buildHeaderCard(ThemeData theme, ColorScheme colorScheme) {
    final isWifi = widget.device.connectionType == ModbusConnectionType.wifi;
    final connColor = isWifi ? AppTheme.primary : AppTheme.secondary;
    final connLabel = isWifi ? 'WiFi' : 'Bluetooth';
    final connIcon = isWifi ? 'wifi' : 'bluetooth';

    return AppCard(
      padding: EdgeInsets.all(3.5.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris atas: nama device + badge jenis sambungan
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.device.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15.sp > 17 ? 17 : 15.sp,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              SizedBox(width: 2.w),
              // Badge jenis sambungan
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: connColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: connColor.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomIconWidget(
                      iconName: connIcon,
                      size: 12,
                      color: connColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      connLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.sp > 12 ? 12 : 11.sp,
                        fontWeight: FontWeight.w600,
                        color: connColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 0.8.h),
          // Alamat IP / MAC
          Row(
            children: [
              CustomIconWidget(
                iconName: isWifi ? 'router' : 'devices',
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                widget.device.address,
                style: GoogleFonts.sourceCodePro(
                  fontSize: 12.sp > 13 ? 13 : 12.sp,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: 1.h),
          Divider(color: colorScheme.outlineVariant, height: 1),
          SizedBox(height: 1.h),
          // Arahan hex yang dijana
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arahan Hex',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.sp > 12 ? 12 : 11.sp,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      commandText,
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 12.sp > 13 ? 13 : 12.sp,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Butang salin arahan
              GestureDetector(
                onTap: () => _copyToClipboard(commandText),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: CustomIconWidget(
                    iconName: 'content_copy',
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          // Respons terakhir (jika ada)
          if (lastResponse != null) ...[
            SizedBox(height: 1.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Respons Terakhir',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.sp > 12 ? 12 : 11.sp,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastResponse!,
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 12.sp > 13 ? 13 : 12.sp,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          // Preview nilai yang didekod (jika ada register values)
          if (registerValues.isNotEmpty &&
              registerValues.any((v) => v != 0)) ...[
            SizedBox(height: 0.8.h),
            Wrap(
              spacing: 2.w,
              runSpacing: 0.5.h,
              children: registerValues
                  .asMap()
                  .entries
                  .take(4) // tunjuk max 4 preview
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Text(
                        'R${e.key}: ${e.value}',
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 11.sp > 12 ? 12 : 11.sp,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── TabBar ─────────────────────────────────────────────────────────────────
  Widget _buildTabBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(10.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13.sp > 14 ? 14 : 13.sp,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13.sp > 14 ? 14 : 13.sp,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'TX / RX Log'),
          Tab(text: 'Register Values'),
        ],
      ),
    );
  }

  // ── Tab 1: Log TX/RX ───────────────────────────────────────────────────────
  Widget _buildTxRxLogTab(ThemeData theme, ColorScheme colorScheme) {
    if (txRxLog.isEmpty) {
      return _buildEmptyState(
        icon: 'swap_horiz',
        message: 'Tiada log lagi.\nMula polling untuk melihat data TX/RX.',
        colorScheme: colorScheme,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
      // Terbaru di atas — reversed list
      reverse: false,
      itemCount: txRxLog.length,
      itemBuilder: (context, index) {
        // Indeks 0 = terbaru (log disimpan terbaru di hadapan)
        final entry = txRxLog[index];
        return _buildLogEntry(entry, colorScheme);
      },
    );
  }

  // ── Satu baris log TX/RX ───────────────────────────────────────────────────
  Widget _buildLogEntry(TxRxLogEntry entry, ColorScheme colorScheme) {
    final isTx = entry.isTx;
    final prefix = isTx ? '[tx]' : '[rx]';
    final prefixColor = entry.isError
        ? AppTheme.errorColor
        : isTx
        ? AppTheme.primary
        : AppTheme.success;
    final timeStr = _formatTime(entry.time);

    return Padding(
      padding: EdgeInsets.only(bottom: 0.6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge TX/RX
          Container(
            width: 11.w,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: prefixColor.withAlpha(20),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Text(
              prefix,
              style: GoogleFonts.sourceCodePro(
                fontSize: 11.sp > 12 ? 12 : 11.sp,
                fontWeight: FontWeight.w700,
                color: prefixColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 2.w),
          // Masa
          Text(
            timeStr,
            style: GoogleFonts.sourceCodePro(
              fontSize: 11.sp > 12 ? 12 : 11.sp,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: 2.w),
          // Data hex
          Expanded(
            child: Text(
              entry.data,
              style: GoogleFonts.sourceCodePro(
                fontSize: 12.sp > 13 ? 13 : 12.sp,
                color: entry.isError
                    ? AppTheme.errorColor
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Register Values ─────────────────────────────────────────────────
  Widget _buildRegisterValuesTab(ThemeData theme, ColorScheme colorScheme) {
    if (registerValues.isEmpty) {
      return _buildEmptyState(
        icon: 'grid_view',
        message: 'Tiada nilai register.\nMula polling untuk membaca data.',
        colorScheme: colorScheme,
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(4.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2.w,
        mainAxisSpacing: 1.5.h,
        childAspectRatio: 1.1,
      ),
      itemCount: registerValues.length,
      itemBuilder: (context, index) {
        return _buildRegisterBox(
          index: index,
          value: registerValues[index],
          colorScheme: colorScheme,
        );
      },
    );
  }

  // ── Kotak nilai satu register ──────────────────────────────────────────────
  Widget _buildRegisterBox({
    required int index,
    required num value,
    required ColorScheme colorScheme,
  }) {
    // Alamat register sebenar = startAddress + index
    final regAddr = widget.device.startAddress + index;
    final addrHex =
        '0x${regAddr.toRadixString(16).padLeft(4, '0').toUpperCase()}';

    return AppCard(
      padding: EdgeInsets.all(2.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Nombor indeks / alamat
          Text(
            addrHex,
            style: GoogleFonts.sourceCodePro(
              fontSize: 10.sp > 11 ? 11 : 10.sp,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 0.5.h),
          // Nilai yang didekod
          Text(
            value.toString(),
            style: GoogleFonts.sourceCodePro(
              fontSize: 14.sp > 16 ? 16 : 14.sp,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 0.3.h),
          // Label indeks
          Text(
            'R$index',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10.sp > 11 ? 11 : 10.sp,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state generik ────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required String icon,
    required String message,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(8.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomIconWidget(
              iconName: icon,
              size: 48,
              color: colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            SizedBox(height: 2.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.sp > 14 ? 14 : 13.sp,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
