import "package:flutter/material.dart";

import "../../theme/app_theme.dart";

/// Bevel-clipped rectangle: all four corners cut by [cutSize] diagonally.
class _BevelClipper extends CustomClipper<Path> {
  _BevelClipper(this.cut);

  final double cut;

  @override
  Path getClip(Size size) => bevelPath(size, cut);

  @override
  bool shouldReclip(covariant _BevelClipper oldClipper) => oldClipper.cut != cut;
}

/// Shared path for panels and toggles.
Path bevelPath(Size size, double c) {
  final double w = size.width;
  final double h = size.height;
  final double x = c.clamp(0.0, w / 2);
  final double y = c.clamp(0.0, h / 2);
  return Path()
    ..moveTo(x, 0)
    ..lineTo(w - x, 0)
    ..lineTo(w, y)
    ..lineTo(w, h - y)
    ..lineTo(w - x, h)
    ..lineTo(x, h)
    ..lineTo(0, h - y)
    ..lineTo(0, y)
    ..close();
}

class _BevelBorderPainter extends CustomPainter {
  _BevelBorderPainter({
    required this.cut,
    required this.borderColor,
    this.topAccentColor,
  });

  final double cut;
  final Color borderColor;
  final Color? topAccentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = bevelPath(size, cut);
    if (topAccentColor != null) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), Paint()..color = topAccentColor!);
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _BevelBorderPainter oldDelegate) {
    return oldDelegate.cut != cut ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.topAccentColor != topAccentColor;
  }
}

/// Angular panel shell: clip, optional fill, hairline border, optional top accent, optional glow.
class ClippedCornerBox extends StatelessWidget {
  const ClippedCornerBox({
    super.key,
    required this.child,
    this.borderColor = AppTheme.kBorder,
    this.backgroundColor,
    this.glowColor,
    this.topAccentColor,
    this.cutSize = 6,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color borderColor;
  final Color? backgroundColor;
  final Color? glowColor;
  final Color? topAccentColor;
  final double cutSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    Widget core = ClipPath(
      clipper: _BevelClipper(cutSize),
      child: ColoredBox(
        color: backgroundColor ?? Colors.transparent,
        child: Padding(padding: padding, child: child),
      ),
    );

    core = Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        core,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BevelBorderPainter(
                cut: cutSize,
                borderColor: borderColor,
                topAccentColor: topAccentColor,
              ),
            ),
          ),
        ),
      ],
    );

    if (glowColor != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ],
        ),
        child: core,
      );
    }
    return core;
  }
}
