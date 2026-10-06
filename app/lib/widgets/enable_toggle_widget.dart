import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class EnableToggleWidget extends StatelessWidget {
  const EnableToggleWidget({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = enabled ? AppTheme.kGo : AppTheme.kStop;
    final Color glow = enabled ? AppTheme.kGo : AppTheme.kStop;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: ClippedCornerBox(
          cutSize: 6,
          backgroundColor: enabled
              ? AppTheme.kGo.withValues(alpha: 0.08)
              : AppTheme.kStop.withValues(alpha: 0.1),
          borderColor: border,
          topAccentColor: enabled ? AppTheme.kGo : AppTheme.kStop,
          glowColor: glow,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    "MTR",
                    style: AppTheme.labelUi(9, color: AppTheme.kTextSec, weight: FontWeight.w600),
                  ),
                  Text(
                    enabled ? "ON" : "OFF",
                    style: AppTheme.labelUi(13,
                        color: enabled ? AppTheme.kGo : AppTheme.kStop, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
