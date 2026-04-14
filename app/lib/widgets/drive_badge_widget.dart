import "package:flutter/material.dart";

import "../core/telemetry_model.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class DriveBadgeWidget extends StatelessWidget {
  const DriveBadgeWidget({super.key, required this.drive});

  final DriveState drive;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color border;
    late final String text;
    late final Color fg;
    switch (drive) {
      case DriveState.fwd:
        bg = AppTheme.kGo.withValues(alpha: 0.22);
        border = AppTheme.kGo;
        text = "▶ FORWARD";
        fg = AppTheme.kGo;
      case DriveState.rev:
        bg = AppTheme.kRev.withValues(alpha: 0.22);
        border = AppTheme.kRev;
        text = "◀ REVERSE";
        fg = AppTheme.kRev;
      case DriveState.stop:
        bg = AppTheme.kDim;
        border = AppTheme.kStop;
        text = "■ STOPPED";
        fg = AppTheme.kTextPri;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> anim) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
            child: child,
          ),
        );
      },
      child: ClippedCornerBox(
        key: ValueKey<DriveState>(drive),
        cutSize: 5,
        backgroundColor: bg,
        borderColor: border,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: AppTheme.labelUi(11, color: fg, weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
