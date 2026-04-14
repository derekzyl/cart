import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "../core/robot_commands.dart";
import "../core/telemetry_model.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "shared/data_chip.dart";
import "shared/panel_label.dart";

class JoystickWidget extends StatefulWidget {
  const JoystickWidget({
    super.key,
    required this.rateHz,
    required this.deadZonePx,
    required this.sensitivityOverride,
    required this.autoMode,
    required this.enabled,
    required this.onCommand,
    required this.telemetry,
  });

  final int rateHz;
  final double deadZonePx;
  final double sensitivityOverride;
  final bool autoMode;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onCommand;
  final Telemetry telemetry;

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  Timer? _timer;
  double _radius = 1;
  /// True while knob is outside dead zone (user is driving/steering from stick).
  bool _stickWasActive = false;
  late final AnimationController _releaseCtrl;
  Animation<Offset>? _releaseAnim;

  @override
  void initState() {
    super.initState();
    _releaseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant JoystickWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rateHz != widget.rateHz) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final int hz = widget.rateHz.clamp(10, 30);
    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round()), (_) => _emitCommand());
  }

  void _emitCommand() {
    final double mag = _offset.distance;
    if (mag < widget.deadZonePx) {
      widget.onCommand(RobotCommands.steer("center", 0));
      // Do not spam move(stop) every tick while centered — that overrides hold-to-drive
      // on the FWD/REV buttons. Only stop when returning to center from an active drag.
      if (_stickWasActive) {
        widget.onCommand(RobotCommands.move("stop"));
        _stickWasActive = false;
      }
      return;
    }

    _stickWasActive = true;
    final double nx = (_offset.dx / _radius).clamp(-1.0, 1.0);
    final double ny = (-_offset.dy / _radius).clamp(-1.0, 1.0);
    final int pwm =
        ((math.max(nx.abs(), ny.abs()) * 255 * widget.sensitivityOverride)).round().clamp(0, 255);

    final String steer = nx > 0.1
        ? "right"
        : nx < -0.1
            ? "left"
            : "center";
    final String move = ny > 0.1
        ? "fwd"
        : ny < -0.1
            ? "rev"
            : "stop";

    widget.onCommand(RobotCommands.steer(steer, pwm));
    widget.onCommand(RobotCommands.move(move));
  }

  void _onDrag(Offset local, Size size) {
    _releaseCtrl.stop();
    _releaseAnim = null;
    final Offset center = Offset(size.width / 2, size.height / 2);
    Offset delta = local - center;
    final double maxR = math.min(size.width, size.height) * 0.38;
    _radius = maxR;
    if (delta.distance > maxR) {
      delta = Offset.fromDirection(delta.direction, maxR);
    }
    setState(() => _offset = delta);
  }

  void _finishDrag() {
    final Offset start = _offset;
    _releaseCtrl.reset();
    _releaseAnim = Tween<Offset>(begin: start, end: Offset.zero).animate(
      CurvedAnimation(parent: _releaseCtrl, curve: Curves.elasticOut),
    );
    _releaseAnim!.addListener(_tickRelease);
    _releaseCtrl.forward().whenComplete(() {
      _releaseAnim?.removeListener(_tickRelease);
      if (mounted) {
        setState(() {
          _offset = Offset.zero;
        });
      }
      widget.onCommand(RobotCommands.steer("center", 0));
      widget.onCommand(RobotCommands.move("stop"));
    });
  }

  void _tickRelease() {
    final Animation<Offset>? a = _releaseAnim;
    if (a == null) {
      return;
    }
    setState(() => _offset = a.value);
  }

  @override
  void dispose() {
    _releaseAnim?.removeListener(_tickRelease);
    _releaseCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _steerChip() {
    final int p = widget.telemetry.steerPwm.clamp(0, 255);
    final int signed = switch (widget.telemetry.drive) {
      DriveState.fwd => p,
      DriveState.rev => -p,
      DriveState.stop => 0,
    };
    return signed == 0 ? "0" : (signed > 0 ? "+$signed" : "$signed");
  }

  String _spdChip() {
    return switch (widget.telemetry.drive) {
      DriveState.fwd => "FWD",
      DriveState.rev => "REV",
      DriveState.stop => "0",
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PanelLabel("STEERING"),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c2) {
                  final double side = math.min(c2.maxWidth * 0.85, c2.maxHeight * 0.7);
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: GestureDetector(
                        onPanDown: (DragDownDetails d) => _onDrag(d.localPosition, Size(side, side)),
                        onPanUpdate: (DragUpdateDetails d) => _onDrag(d.localPosition, Size(side, side)),
                        onPanEnd: (_) => _finishDrag(),
                        onPanCancel: _finishDrag,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            CustomPaint(
                              size: Size(side, side),
                              painter: _HexJoystickPainter(
                                offset: _offset,
                                deadZone: widget.deadZonePx,
                                maxR: side * 0.38,
                              ),
                            ),
                            _knob(side),
                            if (widget.autoMode || !widget.enabled)
                              Positioned.fill(
                                child: ClippedCornerBox(
                                  cutSize: 4,
                                  backgroundColor: AppTheme.kBg.withValues(alpha: 0.72),
                                  borderColor: AppTheme.kBorder,
                                  child: Center(
                                    child: FittedBox(
                                      child: Text(
                                        widget.autoMode ? "AUTO — MANUAL LOCKED" : "DISABLED",
                                        style: AppTheme.labelUi(11, color: AppTheme.kWarn),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: DataChip(label: "STR", value: "[${_steerChip()}]"),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: DataChip(label: "SPD", value: "[${_spdChip()}]"),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _knob(double side) {
    final Offset center = Offset(side / 2, side / 2);
    final double ny = (-_offset.dy / (_radius > 0 ? _radius : 1)).clamp(-1.0, 1.0);
    Color knob = AppTheme.kAccent;
    if (ny > 0.08) {
      knob = AppTheme.kGo;
    } else if (ny < -0.08) {
      knob = AppTheme.kRev;
    }
    return Positioned(
      left: center.dx + _offset.dx - 14,
      top: center.dy + _offset.dy - 14,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: knob,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppTheme.kAccent.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _HexJoystickPainter extends CustomPainter {
  _HexJoystickPainter({
    required this.offset,
    required this.deadZone,
    required this.maxR,
  });

  final Offset offset;
  final double deadZone;
  final double maxR;

  Path _hexPath(Offset c, double r) {
    final Path p = Path();
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + i * math.pi / 3;
      final double x = c.dx + r * math.cos(a);
      final double y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Path hex = _hexPath(c, maxR);
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppTheme.kSurface,
    );
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.kBorder,
    );

    canvas.drawCircle(
      c,
      12,
      Paint()..color = AppTheme.kDim,
    );

    final double labelR = maxR * 1.06;
    _label(canvas, c, labelR, -math.pi / 2, "FWD", _fadeForQuadrant(0, 1));
    _label(canvas, c, labelR, math.pi / 2, "REV", _fadeForQuadrant(0, -1));
    _label(canvas, c, labelR, math.pi, "L", _fadeForQuadrant(-1, 0));
    _label(canvas, c, labelR, 0, "R", _fadeForQuadrant(1, 0));

    if (offset.distance > 0.5) {
      final Paint vec = Paint()
        ..color = AppTheme.kAccent.withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c, c + offset, vec);
    }
  }

  double _fadeForQuadrant(double qx, double qy) {
    final double nx = offset.dx / (maxR > 0 ? maxR : 1);
    final double ny = -offset.dy / (maxR > 0 ? maxR : 1);
    final double d = (nx * qx + ny * qy);
    if (d > 0.25) {
      return 1;
    }
    if (d > 0) {
      return 0.5 + d * 2;
    }
    return 0.45;
  }

  void _label(Canvas canvas, Offset c, double r, double angle, String text, double fade) {
    final Offset p = c + Offset(math.cos(angle), math.sin(angle)) * r;
    final TextSpan span = TextSpan(
      text: text,
      style: AppTheme.monoData(9).copyWith(
        color: Color.lerp(AppTheme.kTextSec, AppTheme.kAccent, fade.clamp(0.0, 1.0)),
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HexJoystickPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.deadZone != deadZone || oldDelegate.maxR != maxR;
  }
}
