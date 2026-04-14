import "package:flutter/material.dart";

import "../../theme/app_theme.dart";

/// Faint tactical grid — static; does not repaint.
class HudGridPainter extends CustomPainter {
  HudGridPainter({this.spacing = 24});

  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = AppTheme.kBorder.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
