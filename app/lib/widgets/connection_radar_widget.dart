import "dart:math" as math;

import "package:flutter/material.dart";

import "../theme/app_theme.dart";

/// Hexagonal tactical radar — driven by [animation] 0…1 loop.
class ConnectionRadarWidget extends StatelessWidget {
  const ConnectionRadarWidget({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _HexRadarPainter(t: animation.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _HexRadarPainter extends CustomPainter {
  _HexRadarPainter({required this.t});

  final double t;

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
    final Offset c = Offset(size.width / 2, size.height * 0.48);
    final double maxR = size.shortestSide * 0.36;

    for (final double scale in <double>[0.33, 0.66, 1.0]) {
      canvas.drawPath(
        _hexPath(c, maxR * scale),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppTheme.kBorder.withValues(alpha: 0.55),
      );
    }

    final double sweepA = -math.pi / 2 + t * math.pi * 2;
    final Offset sweepTip = c + Offset(math.cos(sweepA), math.sin(sweepA)) * maxR;

    canvas.save();
    canvas.clipPath(_hexPath(c, maxR));
    canvas.drawLine(
      c,
      sweepTip,
      Paint()
        ..color = AppTheme.kAccent.withValues(alpha: 0.88)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    for (int i = 0; i < 10; i++) {
      final double seed = i / 10 + t;
      final double ang = math.pi * 0.15 + seed * math.pi * 1.7;
      final double rr = maxR * (0.25 + (math.sin(seed * 6.28 + t * 3) * 0.5 + 0.5) * 0.65);
      final Offset p = c + Offset(math.cos(ang), math.sin(ang)) * rr;
      final double fade = (math.sin(t * math.pi * 2 + i) + 1) / 2;
      canvas.drawCircle(
        p,
        2.2,
        Paint()..color = AppTheme.kAccent.withValues(alpha: 0.15 + fade * 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexRadarPainter oldDelegate) => oldDelegate.t != t;
}
