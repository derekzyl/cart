import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

import "../providers/connection_provider.dart";
import "../providers/settings_provider.dart";
import "../theme/app_theme.dart";
import "../widgets/connection_radar_widget.dart";
import "../widgets/shared/clipped_corner_box.dart";
import "../widgets/wifi_setup_sheet.dart";

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> with TickerProviderStateMixin {
  static const String _robotApSsid = "CartRobot_Setup";
  static const String _robotApIp = "192.168.4.1";

  late final AnimationController _controller;
  late final AnimationController _scanController;
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final FocusNode _ipFocusNode;

  int _ellipsisTick = 0;
  Timer? _ellipsisTimer;

  @override
  void initState() {
    super.initState();
    final ControlSettings s = ref.read(settingsProvider);
    _ipController = TextEditingController(text: s.ip);
    _portController = TextEditingController(text: s.port.toString());
    _ipFocusNode = FocusNode();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _scanController =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _ellipsisTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) {
        setState(() => _ellipsisTick = (_ellipsisTick + 1) % 4);
      }
    });
    unawaited(_autoSelectTargetFromWifi());
  }

  Future<void> _autoSelectTargetFromWifi() async {
    String? ssid;
    try {
      if (Platform.isAndroid) {
        final PermissionStatus status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          return;
        }
      }
      ssid = await NetworkInfo().getWifiName();
    } catch (_) {
      return;
    }

    if (ssid == null || ssid.isEmpty) {
      return;
    }

    final String cleanSsid = ssid.replaceAll('"', "").trim();
    final ControlSettings settings = ref.read(settingsProvider);
    if (cleanSsid != _robotApSsid) {
      return;
    }
    const String nextHost = _robotApIp;
    if (settings.ip == nextHost) {
      return;
    }

    final ControlSettings next = settings.copyWith(ip: nextHost);
    await ref.read(settingsProvider.notifier).update(next);
    if (!mounted) {
      return;
    }
    _ipController.value = TextEditingValue(
      text: nextHost,
      selection: TextSelection.collapsed(offset: nextHost.length),
    );
    unawaited(ref.read(connectionProvider.notifier).connect(nextHost, next.port));
  }

  @override
  void dispose() {
    _ellipsisTimer?.cancel();
    _controller.dispose();
    _scanController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _ipFocusNode.dispose();
    super.dispose();
  }

  void _connect() {
    final String ip = _ipController.text.trim();
    final int port = int.tryParse(_portController.text.trim()) ?? 8080;
    ref.read(settingsProvider.notifier).update(ref.read(settingsProvider).copyWith(ip: ip, port: port));
    ref.read(connectionProvider.notifier).connect(ip, port);
  }

  void _setHostAndConnect(String host) {
    _ipController.text = host;
    final int port = int.tryParse(_portController.text.trim()) ?? 8080;
    ref.read(settingsProvider.notifier).update(ref.read(settingsProvider).copyWith(ip: host, port: port));
    ref.read(connectionProvider.notifier).connect(host, port);
  }

  String _modeFromHost(String host) {
    final String h = host.trim().toLowerCase();
    if (h == _robotApIp) {
      return "AP";
    }
    if (h.endsWith(".local")) {
      return "STA";
    }
    return "STA";
  }

  @override
  Widget build(BuildContext context) {
    final ConnectionUiState connection = ref.watch(connectionProvider);

    final String providerHost = connection.host;
    if (!_ipFocusNode.hasFocus && _ipController.text.trim() != providerHost) {
      _ipController.value = TextEditingValue(
        text: providerHost,
        selection: TextSelection.collapsed(offset: providerHost.length),
      );
    }

    final bool isFailed = connection.status == ConnectionStatus.disconnected;
    final String mode = _modeFromHost(connection.host);
    final String targetText = "${connection.host}:${connection.port}  ($mode mode)";
    final String statusCore = switch (connection.status) {
      ConnectionStatus.connected => "Connected to $targetText",
      ConnectionStatus.connecting => "Connecting to $targetText",
      ConnectionStatus.disconnected =>
        (connection.lastError?.isNotEmpty ?? false)
            ? "${connection.lastError}\nTarget: $targetText"
            : "Disconnected. Target: $targetText",
    };

    final String ell = "." * _ellipsisTick;
    final String attemptLine = connection.status == ConnectionStatus.connecting
        ? "ATTEMPTING CONNECTION$ell"
        : statusCore.toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.kBg,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scanController,
              builder: (BuildContext context, Widget? _) {
                return CustomPaint(
                  painter: _ScanlinePainter(phase: _scanController.value),
                );
              },
            ),
          ),
          Positioned.fill(child: ConnectionRadarWidget(animation: _controller)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Text(
                      "SEARCHING FOR UNIT",
                      textAlign: TextAlign.center,
                      style: AppTheme.displayNum(14, color: AppTheme.kAccent).copyWith(letterSpacing: 4),
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      child: Text(
                        attemptLine,
                        style: AppTheme.monoData(10, color: AppTheme.kTextSec),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      child: Text(
                        "${connection.host}:${connection.port}",
                        style: AppTheme.monoData(11, color: AppTheme.kTextSec),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Robot Hotspot: CartRobot_Setup • Password: cartsetup\nButton Reset: Hold ESP32 BOOT (GPIO 0) or BTN1 for 2s",
                      textAlign: TextAlign.center,
                      style: AppTheme.monoData(11, color: AppTheme.kTextPri),
                    ),
                    const SizedBox(height: 10),
                    // Preset Quick Pickers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _PresetChip(
                          label: "Robot Hotspot",
                          sub: "192.168.4.1",
                          isActive: _ipController.text.trim() == "192.168.4.1",
                          onTap: () => _setHostAndConnect("192.168.4.1"),
                        ),
                        const SizedBox(width: 8),
                        _PresetChip(
                          label: "mDNS Local",
                          sub: "cart-robot.local",
                          isActive: _ipController.text.trim() == "cart-robot.local",
                          onTap: () => _setHostAndConnect("cart-robot.local"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ClippedCornerBox(
                              cutSize: 5,
                              backgroundColor: AppTheme.kPanel,
                              borderColor: AppTheme.kBorder,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: TextField(
                                controller: _ipController,
                                focusNode: _ipFocusNode,
                                keyboardType: TextInputType.text,
                                enableSuggestions: false,
                                autocorrect: false,
                                style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                                cursorColor: AppTheme.kTextPri,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: "192.168.4.1",
                                  hintStyle: AppTheme.labelUi(11, color: AppTheme.kTextSec),
                                ),
                                onSubmitted: (_) => _connect(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: ClippedCornerBox(
                              cutSize: 5,
                              backgroundColor: AppTheme.kPanel,
                              borderColor: AppTheme.kBorder,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: TextField(
                                controller: _portController,
                                keyboardType: TextInputType.number,
                                style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                                cursorColor: AppTheme.kTextPri,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _connect(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _connect,
                          child: ClippedCornerBox(
                            cutSize: 6,
                            backgroundColor: AppTheme.kGlow.withValues(alpha: 0.35),
                            borderColor: AppTheme.kAccent,
                            topAccentColor: AppTheme.kAccent,
                            glowColor: AppTheme.kAccent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                "CONNECT",
                                style: AppTheme.labelUi(13, color: AppTheme.kAccent, weight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () => WifiSetupSheet.show(context),
                          child: ClippedCornerBox(
                            cutSize: 6,
                            backgroundColor: AppTheme.kPanel,
                            borderColor: AppTheme.kAccent.withValues(alpha: 0.6),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const Icon(Icons.wifi_rounded, color: AppTheme.kAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    "ROBOT WI-FI SETUP / SWITCH NETWORK",
                                    style: AppTheme.labelUi(11, color: AppTheme.kAccent, weight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (isFailed) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        "Use the IP shown on the robot LCD (STA or AP).",
                        textAlign: TextAlign.center,
                        style: AppTheme.monoData(10, color: AppTheme.kRecord),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _StatusChip(connection: connection),
          ),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = AppTheme.kBorder.withValues(alpha: 0.15);
    const double step = 3;
    final double off = phase * step * 40;
    for (double y = -off % (step * 40); y < size.height + step * 40; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => oldDelegate.phase != phase;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.connection});

  final ConnectionUiState connection;

  @override
  Widget build(BuildContext context) {
    final String text = switch (connection.status) {
      ConnectionStatus.connected => "CONNECTED",
      ConnectionStatus.connecting => "CONNECTING",
      ConnectionStatus.disconnected => "DISCONNECTED",
    };
    final Color color = switch (connection.status) {
      ConnectionStatus.connected => AppTheme.kGo,
      ConnectionStatus.connecting => AppTheme.kRecord,
      ConnectionStatus.disconnected => AppTheme.kStop,
    };
    return ClippedCornerBox(
      cutSize: 4,
      backgroundColor: color.withValues(alpha: 0.14),
      borderColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(text, style: AppTheme.labelUi(11, color: color, weight: FontWeight.w600)),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.sub,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClippedCornerBox(
        cutSize: 4,
        backgroundColor: isActive ? AppTheme.kAccent.withValues(alpha: 0.15) : AppTheme.kPanel,
        borderColor: isActive ? AppTheme.kAccent : AppTheme.kBorder,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: AppTheme.labelUi(10,
                  color: isActive ? AppTheme.kAccent : AppTheme.kTextPri, weight: FontWeight.w600),
            ),
            Text(
              sub,
              style: AppTheme.monoData(9, color: isActive ? AppTheme.kAccent : AppTheme.kTextSec),
            ),
          ],
        ),
      ),
    );
  }
}
