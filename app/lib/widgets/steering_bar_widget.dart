import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class SteeringBarWidget extends StatelessWidget {
  const SteeringBarWidget({super.key, required this.pwm});

  final int pwm;

  @override
  Widget build(BuildContext context) {
    final double fraction = pwm.clamp(-255, 255) / 255;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double h = constraints.maxHeight.isFinite
            ? constraints.maxHeight.clamp(8.0, 40.0)
            : 24.0;
        return SizedBox(
          height: h,
          child: ClippedCornerBox(
            cutSize: 4,
            backgroundColor: AppTheme.kDim,
            borderColor: AppTheme.kBorder,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c2) {
                final double center = c2.maxWidth / 2;
                final double width = center * fraction.abs();
                final bool right = fraction >= 0;
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(width: 1, color: AppTheme.kTextSec.withValues(alpha: 0.5)),
                      ),
                    ),
                    Positioned(
                      left: right ? center : center - width,
                      width: width,
                      top: 2,
                      bottom: 2,
                      child: ColoredBox(color: AppTheme.kAccent.withValues(alpha: 0.85)),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
