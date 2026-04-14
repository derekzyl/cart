import "dart:math" as math;

import "package:flutter/material.dart";

import "../theme/app_theme.dart";

class ArcGaugeWidget extends StatefulWidget {
  const ArcGaugeWidget({super.key, required this.distanceCm});

  final int distanceCm;

  @override
  State<ArcGaugeWidget> createState() => _ArcGaugeWidgetState();
}

class _ArcGaugeWidgetState extends State<ArcGaugeWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Animation<double>? _anim;
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.distanceCm.toDouble();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void didUpdateWidget(covariant ArcGaugeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.distanceCm != widget.distanceCm) {
      _animateTo(widget.distanceCm.toDouble());
    }
  }

  void _animateTo(double next) {
    _anim?.removeListener(_tick);
    _anim = Tween<double>(begin: _shown, end: next).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _anim!.addListener(_tick);
    _ctrl.forward(from: 0);
  }

  void _tick() {
    final Animation<double>? a = _anim;
    if (a == null) {
      return;
    }
    setState(() => _shown = a.value);
  }

  @override
  void dispose() {
    _anim?.removeListener(_tick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Center(
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: CustomPaint(
              painter: _HudArcPainter(value: _shown),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      FittedBox(
                        child: Text(
                          _shown.round().toString(),
                          style: AppTheme.displayNum(22, color: AppTheme.kTextNum),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FittedBox(
                        child: Text(
                          "cm",
                          style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudArcPainter extends CustomPainter {
  _HudArcPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height * 0.92);
    final double radius = math.min(size.width * 0.44, size.height * 0.82);
    final Rect rect = Rect.fromCircle(center: c, radius: radius);
    const double start = math.pi;
    const double sweep = math.pi;

    Paint zonePaint(Color col, double op) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.butt
      ..color = col.withValues(alpha: op);

    canvas.drawArc(rect, start, sweep * 0.1, false, zonePaint(AppTheme.kStop, 0.55));
    canvas.drawArc(rect, start + sweep * 0.1, sweep * 0.1, false, zonePaint(AppTheme.kWarn, 0.55));
    canvas.drawArc(rect, start + sweep * 0.2, sweep * 0.8, false, zonePaint(AppTheme.kGo, 0.45));

    for (int cm = 0; cm <= 200; cm += 20) {
      final double t = cm / 200.0;
      final double ang = start + t * sweep;
      final bool major = cm == 50 || cm == 100 || cm == 150 || cm == 200;
      final double inner = major ? radius - 20 : radius - 12;
      final Offset o = c + Offset(math.cos(ang), math.sin(ang)) * radius;
      final Offset i = c + Offset(math.cos(ang), math.sin(ang)) * inner;
      canvas.drawLine(
        o,
        i,
        Paint()
          ..color = AppTheme.kBorder.withValues(alpha: 0.85)
          ..strokeWidth = major ? 1.4 : 1,
      );
    }

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.kBorder,
    );

    _cornerAccent(canvas, c, radius, start);
    _cornerAccent(canvas, c, radius, start + sweep);

    final double clamped = value.clamp(0, 200);
    final double t = clamped / 200.0;
    final double angle = start + t * sweep;
    final Offset tip = c + Offset(math.cos(angle), math.sin(angle)) * (radius - 16);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = AppTheme.kAccent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 4, Paint()..color = AppTheme.kAccent);
  }

  void _cornerAccent(Canvas canvas, Offset c, double r, double ang) {
    final Offset p = c + Offset(math.cos(ang), math.sin(ang)) * (r + 2);
    final Paint paint = Paint()
      ..color = AppTheme.kAccent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final Path pth = Path()
      ..moveTo(p.dx - 5, p.dy)
      ..lineTo(p.dx, p.dy)
      ..lineTo(p.dx, p.dy + 5);
    canvas.drawPath(pth, paint);
  }

  @override
  bool shouldRepaint(covariant _HudArcPainter oldDelegate) => oldDelegate.value != value;
}
