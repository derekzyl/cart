import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "../core/robot_commands.dart";
import "../core/telemetry_model.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "shared/panel_label.dart";

class JoystickWidget extends StatefulWidget {
  const JoystickWidget({
    super.key,
    required this.rateHz,
    required this.deadZonePx,
    required this.sensitivityOverride,
    required this.holdSteer,
    required this.onHoldSteerChanged,
    required this.autoMode,
    required this.enabled,
    required this.onCommand,
    required this.telemetry,
  });

  final int rateHz;
  final double deadZonePx;
  final double sensitivityOverride;
  final bool holdSteer;
  final ValueChanged<bool> onHoldSteerChanged;
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
  bool _fingerDown = false;
  /// Finger is up in HOLD. Steer was already sent; only drive keeps refreshing.
  bool _parked = false;
  String? _lastSteer;
  int? _lastPwm;
  String? _lastMove;
  double? _lastSteerAngle;
  DateTime _lastDriveSent = DateTime.fromMillisecondsSinceEpoch(0);
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
    if (oldWidget.holdSteer && !widget.holdSteer && _offset.distance > 1) {
      _finishDrag();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final int hz = widget.rateHz.clamp(10, 30);
    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round()), (_) => _emitCommand());
  }

  void _emitDrive(String steer, int pwm, String move) {
    final double signed = steer == "left" ? -1.0 : (steer == "right" ? 1.0 : 0.0);
    final double angle = steer == "center"
        ? 0.0
        : (signed * (pwm / 255.0) * 30.0 * widget.sensitivityOverride).clamp(-30.0, 30.0);

    final bool dirChanged = steer != _lastSteer;
    final bool angleShift8Deg = _lastSteerAngle == null ||
        (angle - _lastSteerAngle!).abs() >= 8.0;
    final bool steerChanged = dirChanged || (steer != "center" && angleShift8Deg);
    final bool moveChanged = move != _lastMove;
    final bool heartbeat =
        DateTime.now().difference(_lastDriveSent) >= const Duration(milliseconds: 800);

    if (!steerChanged && !moveChanged && !heartbeat) {
      return;
    }

    if (steerChanged) {
      _lastSteer = steer;
      _lastPwm = pwm;
      _lastSteerAngle = angle;
      if (steer == "center" || pwm == 0) {
        widget.onCommand(RobotCommands.steer("center", 0));
        widget.onCommand(RobotCommands.straight());
      } else {
        widget.onCommand(RobotCommands.steer(steer, pwm));
        widget.onCommand(RobotCommands.steerAngle(angle));
      }
    }

    if (moveChanged || heartbeat) {
      _lastMove = move;
      _lastDriveSent = DateTime.now();
      if (move != "stop" || moveChanged) {
        widget.onCommand(RobotCommands.move(move));
      }
    }
  }

  String _moveFor(double ny) {
    if (ny > 0.1) {
      return "fwd";
    }
    if (ny < -0.1) {
      return "rev";
    }
    return "stop";
  }

  void _emitMoveOnly(String move) {
    final bool changed = move != _lastMove;
    final bool heartbeat =
        DateTime.now().difference(_lastDriveSent) >= const Duration(milliseconds: 800);
    if (!changed && !heartbeat) {
      return;
    }
    _lastMove = move;
    _lastDriveSent = DateTime.now();
    if (move != "stop" || changed) {
      widget.onCommand(RobotCommands.move(move));
    }
  }

  void _emitCommand() {
    if (_releaseCtrl.isAnimating) {
      return;
    }
    final double mag = _offset.distance;
    final double r = _radius > 0 ? _radius : 1.0;
    final double normDist = (mag / r).clamp(0.0, 1.0);
    final double dx = _offset.dx;
    final double dy = _offset.dy;
    final double ny = (-dy / r).clamp(-1.0, 1.0);

    if (_parked && !_fingerDown && mag >= widget.deadZonePx) {
      _emitMoveOnly(_moveFor(ny));
      return;
    }
    if (mag < widget.deadZonePx) {
      _parked = false;
      if (_stickWasActive) {
        _stickWasActive = false;
        if (_fingerDown) {
          _emitMoveOnly("stop");
        }
      }
      return;
    }

    _stickWasActive = true;

    // Compass heading in degrees: 0° = FWD, 90° = R, 180° = REV, 270° = L
    double heading = math.atan2(dx, -dy) * (180.0 / math.pi);
    if (heading < 0) {
      heading += 360.0;
    }

    // Straight deadbands around pure forward (0°) and pure reverse (180°)
    const double straightBand = 14.0;
    final bool isStraightFwd = heading <= straightBand || heading >= (360.0 - straightBand);
    final bool isStraightRev = (heading - 180.0).abs() <= straightBand;

    String steer = "center";
    String move = "stop";

    if (ny > 0.10) {
      move = "fwd";
    } else if (ny < -0.10) {
      move = "rev";
    }

    if (isStraightFwd) {
      move = "fwd";
      steer = "center";
    } else if (isStraightRev) {
      move = "rev";
      steer = "center";
    } else if (heading > straightBand && heading < (180.0 - straightBand)) {
      // 0° to 90° (fwd-r) and 90° to 180° (r-rev) -> steer RIGHT
      steer = "right";
    } else if (heading > (180.0 + straightBand) && heading < (360.0 - straightBand)) {
      // 180° to 270° (rev-l) and 270° to 360° (l-fwd) -> steer LEFT
      steer = "left";
    }

    // Lateral displacement controls steer strength (0 along straight axis, max at 90° / 270°)
    final double lateral = math.sin(heading * math.pi / 180.0).abs() * normDist;
    final int pwm = steer == "center" ? 0 : (lateral * 255).round().clamp(0, 255);

    _emitDrive(steer, pwm, move);
  }

  void _onDrag(Offset local, Size size) {
    _fingerDown = true;
    _parked = false;
    _releaseCtrl.stop();
    _releaseAnim = null;
    final Offset center = Offset(size.width / 2, size.height / 2);
    Offset delta = local - center;
    final double maxR = math.min(size.width, size.height) * 0.36;
    _radius = maxR;
    if (delta.distance > maxR) {
      delta = Offset.fromDirection(delta.direction, maxR);
    }
    setState(() => _offset = delta);
  }

  void _finishDrag() {
    _fingerDown = false;
    if (widget.holdSteer && _offset.distance >= widget.deadZonePx) {
      _parked = true;
      return;
    }
    _parked = false;
    widget.onCommand(RobotCommands.move("stop"));
    _lastMove = "stop";
    _lastDriveSent = DateTime.now();
    widget.onCommand(RobotCommands.steer("center", 0));
    widget.onCommand(RobotCommands.straight());
    _lastSteer = "center";
    _lastPwm = 0;
    _lastSteerAngle = 0.0;
    final Offset start = _offset;
    _releaseCtrl.reset();
    // easeOut stays on the same side of center. elasticOut crosses to the
    // other side and that was sent as a full opposite steer.
    _releaseAnim = Tween<Offset>(begin: start, end: Offset.zero).animate(
      CurvedAnimation(parent: _releaseCtrl, curve: Curves.easeOut),
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
      widget.onCommand(RobotCommands.straight());
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelLabel("STEER"),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Text(
              "DZ ${widget.deadZonePx.toStringAsFixed(0)}",
              style: AppTheme.monoData(9, color: AppTheme.kTextNum),
            ),
            const SizedBox(width: 8),
            Text(
              "REACH ${widget.sensitivityOverride.toStringAsFixed(1)}",
              style: AppTheme.monoData(9, color: AppTheme.kTextNum),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => widget.onHoldSteerChanged(!widget.holdSteer),
          child: ClippedCornerBox(
            cutSize: 4,
            backgroundColor: widget.holdSteer ? AppTheme.kWarn.withValues(alpha: 0.22) : AppTheme.kDim,
            borderColor: widget.holdSteer ? AppTheme.kWarn : AppTheme.kAccent,
            topAccentColor: widget.holdSteer ? AppTheme.kWarn : AppTheme.kAccent,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                widget.holdSteer ? "HOLD ON" : "HOLD OFF",
                style: AppTheme.labelUi(12, color: widget.holdSteer ? AppTheme.kWarn : AppTheme.kAccent),
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c2) {
              final Size area = Size(c2.maxWidth, c2.maxHeight);
              final double maxR = math.min(area.width, area.height) * 0.36;
              final bool playing = widget.telemetry.routeState == RouteState.playing ||
                  widget.telemetry.routeState == RouteState.playingReverse;
              final Offset shown = playing && _offset.distance < 0.5 ? _playbackOffset(maxR) : _offset;
              return GestureDetector(
                onPanDown: (DragDownDetails d) => _onDrag(d.localPosition, area),
                onPanUpdate: (DragUpdateDetails d) => _onDrag(d.localPosition, area),
                onPanEnd: (_) => _finishDrag(),
                onPanCancel: _finishDrag,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    CustomPaint(
                      size: area,
                      painter: _HexJoystickPainter(
                        offset: shown,
                        deadZone: widget.deadZonePx,
                        maxR: maxR,
                        distanceCm: widget.telemetry.distCm,
                      ),
                    ),
                    _knob(area, shown, animate: playing),
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
              );
            },
          ),
        ),
      ],
    );
  }

  Offset _playbackOffset(double maxR) {
    double shown = widget.telemetry.steerAngle % 360.0;
    if (shown < 0) {
      shown += 360.0;
    }
    if (shown > 180.0) {
      shown -= 360.0;
    }
    final double steer = (shown / 180.0).clamp(-1.0, 1.0);
    final double drive = switch (widget.telemetry.drive) {
      DriveState.fwd => -1.0,
      DriveState.rev => 1.0,
      DriveState.stop => 0.0,
    };
    Offset delta = Offset(steer * maxR, drive * maxR);
    if (delta.distance > maxR) {
      delta = Offset.fromDirection(delta.direction, maxR);
    }
    return delta;
  }

  Widget _knob(Size area, Offset offset, {required bool animate}) {
    final Offset center = Offset(area.width / 2, area.height / 2);
    final double ny = (-offset.dy / (_radius > 0 ? _radius : 1)).clamp(-1.0, 1.0);
    Color knob = AppTheme.kAccent;
    if (ny > 0.08) {
      knob = AppTheme.kGo;
    } else if (ny < -0.08) {
      knob = AppTheme.kRev;
    }
    return AnimatedPositioned(
      duration: animate ? const Duration(milliseconds: 140) : Duration.zero,
      curve: Curves.easeOut,
      left: center.dx + offset.dx - 14,
      top: center.dy + offset.dy - 14,
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
    required this.distanceCm,
  });

  final Offset offset;
  final double deadZone;
  final double maxR;
  final int distanceCm;

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

  Color _rangeColor() {
    if (distanceCm < 0) {
      return AppTheme.kTextSec;
    }
    if (distanceCm < 25) {
      return AppTheme.kStop;
    }
    if (distanceCm < 60) {
      return AppTheme.kWarn;
    }
    return AppTheme.kGo;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Color range = _rangeColor();
    final double radarR = math.min(maxR * 1.18, math.min(size.width, size.height) * 0.46);

    for (final double scale in <double>[0.42, 0.7, 1.0]) {
      canvas.drawCircle(
        c,
        radarR * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppTheme.kBorder.withValues(alpha: 0.7),
      );
    }

    final bool live = distanceCm >= 0;
    final double clamped = live ? distanceCm.clamp(0, 200).toDouble() : 0;
    final Rect arcRect = Rect.fromCircle(center: c, radius: radarR);
    canvas.drawArc(
      arcRect,
      -math.pi * 0.15,
      math.pi * 1.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = range.withValues(alpha: 0.28),
    );
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      (clamped / 200.0) * math.pi * 1.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = range.withValues(alpha: 0.95),
    );

    final Path hex = _hexPath(c, maxR * 0.92);
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppTheme.kSurface.withValues(alpha: 0.92),
    );
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = range.withValues(alpha: 0.55),
    );

    canvas.drawCircle(c, 11, Paint()..color = AppTheme.kDim);
    final double zone = deadZone.clamp(6.0, maxR);
    canvas.drawCircle(
      c,
      zone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.kAccent.withValues(alpha: 0.45),
    );

    final TextPainter dist = TextPainter(
      text: TextSpan(
        text: live ? "$distanceCm" : "--",
        style: AppTheme.displayNum(13, color: range),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final TextPainter unit = TextPainter(
      text: TextSpan(
        text: " cm",
        style: AppTheme.labelUi(8, color: AppTheme.kTextSec),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double textW = dist.width + unit.width;
    final double textTop = c.dy - radarR - dist.height - 2;
    final double textY = textTop < 0 ? 0 : textTop;
    dist.paint(canvas, Offset(c.dx - textW / 2, textY));
    unit.paint(canvas, Offset(c.dx - textW / 2 + dist.width, textY + dist.height - unit.height));

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
    return oldDelegate.offset != offset ||
        oldDelegate.deadZone != deadZone ||
        oldDelegate.maxR != maxR ||
        oldDelegate.distanceCm != distanceCm;
  }
}
