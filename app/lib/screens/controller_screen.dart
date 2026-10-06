import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/robot_commands.dart";
import "../core/telemetry_model.dart";
import "../providers/connection_provider.dart";
import "../providers/control_provider.dart";
import "../providers/route_provider.dart";
import "../providers/settings_provider.dart";
import "../providers/telemetry_provider.dart";
import "../theme/app_theme.dart";
import "../widgets/auto_toggle_widget.dart";
import "../widgets/enable_toggle_widget.dart";
import "../widgets/joystick_widget.dart";
import "../widgets/led_buzzer_controls_widget.dart";
import "../widgets/route_panel_widget.dart";
import "../widgets/settings_sheet_widget.dart";
import "../widgets/shared/clipped_corner_box.dart";
import "../widgets/shared/hud_grid_painter.dart";
import "../widgets/speed_controls_widget.dart";
import "../widgets/telemetry_panel_widget.dart";
import "../widgets/wifi_setup_sheet.dart";

class ControllerScreen extends ConsumerStatefulWidget {
  const ControllerScreen({super.key});

  @override
  ConsumerState<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends ConsumerState<ControllerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _connPulse;

  @override
  void initState() {
    super.initState();
    _connPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _connPulse.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: const SettingsSheetWidget(),
      ),
    );
    if (!mounted) {
      return;
    }
    final ControlSettings s = ref.read(settingsProvider);
    ref.read(connectionProvider.notifier).connect(s.ip, s.port);
  }

  void _openWifiSetup() {
    WifiSetupSheet.show(context);
  }

  String _uptime(int s) {
    final int h = s ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    final int sec = s % 60;
    return "${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}:${sec.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final ConnectionUiState connection = ref.watch(connectionProvider);
    final ControlSettings settings = ref.watch(settingsProvider);
    final ControlState controls = ref.watch(controlProvider);
    final RouteUiState route = ref.watch(routeProvider);
    final Telemetry telemetry = ref.watch(telemetryProvider).value ?? Telemetry.initial;
    final ControlNotifier controlNotifier = ref.read(controlProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(painter: HudGridPainter()),
                ),
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        flex: 34,
                        child: _panelPad(
                          child: JoystickWidget(
                            rateHz: settings.commandRateHz,
                            deadZonePx: settings.deadZonePx,
                            sensitivityOverride: settings.sensitivityOverride,
                            autoMode: controls.auto,
                            enabled: controls.enabled,
                            telemetry: telemetry,
                            onCommand: controlNotifier.sendCommand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: 24,
                        child: _panelPad(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                flex: 2,
                                child: EnableToggleWidget(
                                  enabled: controls.enabled,
                                  onTap: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.enable(!controls.enabled));
                                  },
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                flex: 2,
                                child: AutoToggleWidget(
                                  enabled: controls.auto,
                                  onTap: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.auto(!controls.auto));
                                  },
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                flex: 7,
                                child: SpeedControlsWidget(
                                  onFwdDown: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.move("fwd"));
                                  },
                                  onFwdUp: () async {
                                    await controlNotifier.lightHaptic();
                                    controlNotifier.sendCommand(RobotCommands.move("stop"));
                                  },
                                  onRevDown: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.move("rev"));
                                  },
                                  onRevUp: () async {
                                    await controlNotifier.lightHaptic();
                                    controlNotifier.sendCommand(RobotCommands.move("stop"));
                                  },
                                  onStop: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.move("stop"));
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: 42,
                        child: _panelPad(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                flex: 5,
                                child: TelemetryPanelWidget(telemetry: telemetry),
                              ),
                              Container(height: 1, color: AppTheme.kBorder.withValues(alpha: 0.6)),
                              Expanded(
                                flex: 5,
                                child: RoutePanelWidget(
                                  state: route,
                                  onRecordToggle: () async {
                                    await controlNotifier.heavyHaptic();
                                    final String action =
                                        route.state == RouteState.recording ? "record_stop" : "record_start";
                                    controlNotifier.sendCommand(RobotCommands.route(action));
                                  },
                                  onPlayback: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.route("playback"));
                                  },
                                  onReturn: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.route("playback_reverse"));
                                  },
                                  onStop: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.route("stop"));
                                  },
                                  onClearMemory: () async {
                                    await controlNotifier.heavyHaptic();
                                    controlNotifier.sendCommand(RobotCommands.route("clear"));
                                  },
                                ),
                              ),
                              Container(height: 1, color: AppTheme.kBorder.withValues(alpha: 0.6)),
                              Expanded(
                                flex: 3,
                                child: LedBuzzerControlsWidget(
                                  navLeds: controls.navLeds,
                                  headlight: controls.headlight,
                                  buzzerMuted: controls.buzzerMuted,
                                  steeringActive: telemetry.steerPwm > 12,
                                  onNavLeds: (bool v) => controlNotifier.sendCommand(RobotCommands.ledsNav(v)),
                                  onHeadlight: (bool v) => controlNotifier.sendCommand(RobotCommands.headlight(v)),
                                  onBuzzerMuted: (bool v) => controlNotifier.sendCommand(RobotCommands.buzzerMute(v)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _TopStatusBar(
                    connection: connection,
                    telemetry: telemetry,
                    uptimeText: _uptime(telemetry.uptimeS),
                    pulse: _connPulse,
                    onSettings: _openSettings,
                    onWifiSetup: _openWifiSetup,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _panelPad({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: ClippedCornerBox(
        cutSize: 6,
        backgroundColor: AppTheme.kSurface,
        borderColor: AppTheme.kBorder,
        padding: const EdgeInsets.all(6),
        child: child,
      ),
    );
  }
}

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.connection,
    required this.telemetry,
    required this.uptimeText,
    required this.pulse,
    required this.onSettings,
    required this.onWifiSetup,
  });

  final ConnectionUiState connection;
  final Telemetry telemetry;
  final String uptimeText;
  final Animation<double> pulse;
  final VoidCallback onSettings;
  final VoidCallback onWifiSetup;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = switch (connection.status) {
      ConnectionStatus.connected => AppTheme.kGo,
      ConnectionStatus.connecting => AppTheme.kWarn,
      ConnectionStatus.disconnected => AppTheme.kDim,
    };

    final Color? pingColor = connection.latencyMs == null
        ? null
        : (connection.latencyMs! < 50)
            ? AppTheme.kGo
            : (connection.latencyMs! < 150)
                ? AppTheme.kWarn
                : AppTheme.kStop;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.kSurface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: AppTheme.kBorder.withValues(alpha: 0.9)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          AnimatedBuilder(
            animation: pulse,
            builder: (BuildContext context, Widget? _) {
              final double op = connection.status == ConnectionStatus.connected ? 0.45 + pulse.value * 0.55 : 1;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: op),
                  shape: BoxShape.circle,
                  boxShadow: connection.status == ConnectionStatus.connected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: AppTheme.kAccent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onWifiSetup,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: telemetry.wifiMode == "sta" ? AppTheme.kAccent : AppTheme.kWarn,
                ),
                color: (telemetry.wifiMode == "sta" ? AppTheme.kAccent : AppTheme.kWarn).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.wifi_rounded,
                    size: 11,
                    color: telemetry.wifiMode == "sta" ? AppTheme.kAccent : AppTheme.kWarn,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    telemetry.wifiMode == "sta" ? "STA ${telemetry.ip}" : "AP 192.168.4.1",
                    style: AppTheme.monoData(
                      9,
                      color: telemetry.wifiMode == "sta" ? AppTheme.kAccent : AppTheme.kWarn,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                "${connection.host}:${connection.port}",
                style: AppTheme.monoData(10, color: AppTheme.kTextSec),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: FittedBox(
              child: Text(
                "ROBOT CONTROL",
                style: AppTheme.displayNum(11, color: AppTheme.kAccent).copyWith(letterSpacing: 3),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                FittedBox(
                  child: Text(
                    uptimeText,
                    style: AppTheme.monoData(10, color: AppTheme.kTextPri),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: "Wi-Fi setup",
                  onPressed: onWifiSetup,
                  icon: const Icon(Icons.wifi_rounded, size: 18, color: AppTheme.kAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: "Connection settings",
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings, size: 18, color: AppTheme.kAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.kBorder),
                    color: AppTheme.kPanel,
                  ),
                  child: FittedBox(
                    child: Text(
                      "${connection.latencyMs?.toString() ?? "--"} ms",
                      style: AppTheme.monoData(10, color: pingColor ?? AppTheme.kTextSec),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
