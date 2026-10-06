import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class AutoToggleWidget extends StatefulWidget {
  const AutoToggleWidget({super.key, required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<AutoToggleWidget> createState() => _AutoToggleWidgetState();
}

class _AutoToggleWidgetState extends State<AutoToggleWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AutoToggleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _pulse.repeat(reverse: true);
    } else if (!widget.enabled && oldWidget.enabled) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, Widget? child) {
          final double g = widget.enabled ? 0.25 + _pulse.value * 0.35 : 0;
          return ClippedCornerBox(
            cutSize: 5,
            backgroundColor: widget.enabled ? AppTheme.kWarn.withValues(alpha: 0.12) : AppTheme.kDim,
            borderColor: widget.enabled ? AppTheme.kWarn : AppTheme.kBorder,
            topAccentColor: widget.enabled ? AppTheme.kWarn : null,
            glowColor: widget.enabled ? AppTheme.kWarn.withValues(alpha: g) : null,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: FittedBox(
                child: Text(
                  "AUTO",
                  style: AppTheme.labelUi(12,
                      color: widget.enabled ? AppTheme.kWarn : AppTheme.kTextSec, weight: FontWeight.w600),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
