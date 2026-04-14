import "package:flutter/material.dart";

import "../../theme/app_theme.dart";
import "clipped_corner_box.dart";

/// 36×18 angular toggle — no Material [Switch].
class CompactToggle extends StatelessWidget {
  const CompactToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = AppTheme.kGo,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 18,
        child: ClipPath(
          clipper: _TinyBevelClipper(3),
          child: Stack(
            children: <Widget>[
              ColoredBox(color: value ? activeColor.withValues(alpha: 0.45) : AppTheme.kDim),
              AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: value ? AppTheme.kTextPri : AppTheme.kTextSec,
                      boxShadow: value
                          ? <BoxShadow>[
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.35),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _TinyBorderPainter(value ? activeColor : AppTheme.kBorder),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyBevelClipper extends CustomClipper<Path> {
  _TinyBevelClipper(this.c);

  final double c;

  @override
  Path getClip(Size size) => bevelPath(size, c);

  @override
  bool shouldReclip(covariant _TinyBevelClipper old) => old.c != c;
}

class _TinyBorderPainter extends CustomPainter {
  _TinyBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      bevelPath(size, 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TinyBorderPainter oldDelegate) => oldDelegate.color != color;
}
