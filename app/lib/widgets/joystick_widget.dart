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
  String? _lastSteer;
  int? _lastPwm;
  String? _lastMove;
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
  }

  void _startTimer() {
    _timer?.cancel();
    final int hz = widget.rateHz.clamp(10, 30);
    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round()), (_) => _emitCommand());
  }

  void _emitDrive(String steer, int pwm, String move) {
    final bool changed = steer != _lastSteer || pwm != _lastPwm || move != _lastMove;
    final bool heartbeat =
        DateTime.now().difference(_lastDriveSent) >= const Duration(milliseconds: 800);
    if (!changed && !heartbeat) {
      return;
    }
    _lastSteer = steer;
    _lastPwm = pwm;
    _lastMove = move;
    _lastDriveSent = DateTime.now();
    widget.onCommand(RobotCommands.steer(steer, pwm));
    if (move != "stop" || changed) {
      widget.onCommand(RobotCommands.move(move));
    }
  }

  void _emitCommand() {
    final double mag = _offset.distance;
    if (mag < widget.deadZonePx) {
      // move(stop) is sent only when the command changes, so a Forward hold
      // is not cancelled by the centered stick.
      if (_stickWasActive) {
        _stickWasActive = false;
      }
      _emitDrive("center", 0, "stop");
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

    _emitDrive(steer, pwm, move);
  }

  void _onDrag(Offset local, Size size) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelLabel("STEER"),
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
    final double steer = switch (widget.telemetry.steerDir) {
          "left" => -1.0,
          "right" => 1.0,
          _ => 0.0,
        } *
        (widget.telemetry.steerPwm / 255.0);
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
