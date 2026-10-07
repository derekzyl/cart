import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/robot_commands.dart";
import "../providers/connection_provider.dart";
import "../providers/control_provider.dart";
import "../providers/telemetry_provider.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class SteerCalibWidget extends ConsumerStatefulWidget {
  const SteerCalibWidget({super.key});

  @override
  ConsumerState<SteerCalibWidget> createState() => _SteerCalibWidgetState();
}

class _SteerCalibWidgetState extends ConsumerState<SteerCalibWidget> {
  final TextEditingController _right = TextEditingController(text: "90");
  final TextEditingController _left = TextEditingController(text: "90");
  final TextEditingController _travel = TextEditingController(text: "800");
  final TextEditingController _min = TextEditingController(text: "330");
  final TextEditingController _max = TextEditingController(text: "30");
  final TextEditingController _trim = TextEditingController(text: "0");
  final TextEditingController _dead = TextEditingController(text: "40");
  final TextEditingController _band = TextEditingController(text: "3");
  bool _restBothOn = false;
  bool _activeLow = false;
  String _note = "Motors on. Left side of the stick is left, full at 270°. Right side is right, full at 90°. Forward and reverse use the same side.";
  Timer? _jog;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(websocketServiceProvider).messages.listen(_onMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(controlProvider.notifier).sendCommand(RobotCommands.getCalib());
    });
  }

  @override
  void dispose() {
    _jog?.cancel();
    _sub?.cancel();
    _right.dispose();
    _left.dispose();
    _travel.dispose();
    _min.dispose();
    _max.dispose();
    _trim.dispose();
    _dead.dispose();
    _band.dispose();
    super.dispose();
  }

  void _onMessage(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded["cmd"] != "calib") {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _right.text = _num(decoded["right_dps"]);
        _left.text = _num(decoded["left_dps"]);
        _travel.text = _num(decoded["full_travel_ms"]);
        _min.text = _num(decoded["min_deg"]);
        _max.text = _num(decoded["max_deg"]);
        _trim.text = _num(decoded["centre_trim"]);
        _dead.text = _num(decoded["dead_time_ms"]);
        _band.text = _num(decoded["deadband_deg"]);
        _restBothOn = decoded["rest_both_on"] == true;
        _activeLow = decoded["relay_active_low"] == true;
      });
    } catch (_) {}
  }

  String _num(dynamic v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    }
    return "$v";
  }

  void _send(Map<String, dynamic> cmd) {
    ref.read(controlProvider.notifier).sendCommand(cmd);
  }

  Map<String, dynamic> _fields() {
    double d(TextEditingController c, double fallback) => double.tryParse(c.text.trim()) ?? fallback;
    return <String, dynamic>{
      "right_dps": d(_right, 90),
      "left_dps": d(_left, 90),
      "full_travel_ms": d(_travel, 800).round(),
      "min_deg": d(_min, 330),
      "max_deg": d(_max, 30),
      "centre_trim": d(_trim, 0),
      "dead_time_ms": d(_dead, 40).round(),
      "deadband_deg": d(_band, 3),
      "rest_both_on": _restBothOn,
      "relay_active_low": _activeLow,
    };
  }

  void _jogDown(String dir) {
    _jog?.cancel();
    _send(RobotCommands.calibJog(dir, 100));
    _jog = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _send(RobotCommands.calibJog(dir, 100));
    });
  }

  void _jogUp() {
    _jog?.cancel();
    _jog = null;
    _send(RobotCommands.calibJog("right", 0));
  }

  @override
  Widget build(BuildContext context) {
    final double angle = ref.watch(telemetryProvider).value?.steerAngle ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text("STEERING", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
        const SizedBox(height: 6),
        Text(_note, style: AppTheme.labelUi(10, color: AppTheme.kTextSec)),
        const SizedBox(height: 8),
        Text(
          "Wheel ${angle.toStringAsFixed(0)}°",
          style: AppTheme.displayNum(18, color: AppTheme.kTextNum),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(child: _hold("NUDGE LEFT", () => _jogDown("left"))),
            const SizedBox(width: 8),
            Expanded(child: _hold("NUDGE RIGHT", () => _jogDown("right"))),
          ],
        ),
        const SizedBox(height: 10),
        _action("1. This position is center", () {
          _send(RobotCommands.calibSetCentre());
          setState(() => _note = "Center saved. Letting go of the stick comes back here.");
        }),
        const SizedBox(height: 6),
        _action("2. Use 330° left and 30° right", () {
          _min.text = "330";
          _max.text = "30";
          _travel.text = "800";
          _send(RobotCommands.setCalib(_fields()));
          _send(RobotCommands.calibSave());
          setState(() => _note = "Stops saved. Right cannot run past 30°. Left cannot run past 330°.");
        }),
        const SizedBox(height: 6),
        _action("3. Return to center", () => _send(RobotCommands.recentre())),
        const SizedBox(height: 12),
        Text("OPTIONAL SPEED CHECK", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
        const SizedBox(height: 6),
        Text(
          "From center, start a side, then stop when the wheel hits that stop. Each stop is 30° from center.",
          style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
        ),
        const SizedBox(height: 6),
        _action("Start moving right", () {
          _send(RobotCommands.calibMeasureStart("right"));
          setState(() => _note = "Moving right. Tap stop when it reaches the right stop.");
        }),
        const SizedBox(height: 6),
        _action("Stop — that was 30° right", () {
          _send(RobotCommands.calibMeasureStop(30));
          Future<void>.delayed(const Duration(milliseconds: 300), () => _send(RobotCommands.getCalib()));
          setState(() => _note = "Right speed saved from a 30° move.");
        }),
        const SizedBox(height: 6),
        _action("Start moving left", () {
          _send(RobotCommands.calibMeasureStart("left"));
          setState(() => _note = "Moving left. Tap stop at the left stop.");
        }),
        const SizedBox(height: 6),
        _action("Stop — that was 30° left", () {
          _send(RobotCommands.calibMeasureStop(30));
          Future<void>.delayed(const Duration(milliseconds: 300), () => _send(RobotCommands.getCalib()));
          setState(() => _note = "Left speed saved. Tap save if you changed the numbers below.");
        }),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text("Numbers", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
          children: <Widget>[
            _field("Right deg/sec", _right),
            _field("Left deg/sec", _left),
            _field("Time to cross, ms", _travel),
            _field("Left stop deg", _min),
            _field("Right stop deg", _max),
            _field("Center trim deg", _trim),
            _field("Pause between directions, ms", _dead),
            _field("Center deadband deg", _band),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Rest both relays on", style: AppTheme.labelUi(11)),
              value: _restBothOn,
              onChanged: (bool v) => setState(() => _restBothOn = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Relays active low", style: AppTheme.labelUi(11)),
              value: _activeLow,
              onChanged: (bool v) => setState(() => _activeLow = v),
            ),
            _action("Save numbers", () {
              _send(RobotCommands.setCalib(_fields()));
              _send(RobotCommands.calibSave());
              setState(() => _note = "Saved. These stay after a reboot.");
            }),
            const SizedBox(height: 6),
            _action("Reset to 330° / 30°", () => _send(RobotCommands.calibReset())),
          ],
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: AppTheme.monoData(12, color: AppTheme.kTextPri),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Widget _hold(String label, VoidCallback down) {
    return GestureDetector(
      onTapDown: (_) => down(),
      onTapUp: (_) => _jogUp(),
      onTapCancel: _jogUp,
      child: ClippedCornerBox(
        cutSize: 4,
        backgroundColor: AppTheme.kDim,
        borderColor: AppTheme.kAccent,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(child: Text(label, style: AppTheme.labelUi(11, color: AppTheme.kAccent))),
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClippedCornerBox(
        cutSize: 4,
        backgroundColor: AppTheme.kSurface,
        borderColor: AppTheme.kBorder,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(label, style: AppTheme.labelUi(11, color: AppTheme.kTextPri)),
      ),
    );
  }
}
