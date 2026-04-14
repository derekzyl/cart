import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class SpeedControlsWidget extends StatefulWidget {
  const SpeedControlsWidget({
    super.key,
    required this.onFwdDown,
    required this.onFwdUp,
    required this.onRevDown,
    required this.onRevUp,
    required this.onStop,
  });

  final VoidCallback onFwdDown;
  final VoidCallback onFwdUp;
  final VoidCallback onRevDown;
  final VoidCallback onRevUp;
  final VoidCallback onStop;

  @override
  State<SpeedControlsWidget> createState() => _SpeedControlsWidgetState();
}

class _SpeedControlsWidgetState extends State<SpeedControlsWidget> {
  bool _fwd = false;
  bool _rev = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: _hold(
            label: "▲ FWD",
            active: _fwd,
            base: AppTheme.kDim,
            activeFill: AppTheme.kGo,
            border: AppTheme.kGo,
            onDown: () {
              setState(() => _fwd = true);
              widget.onFwdDown();
            },
            onUp: () {
              setState(() => _fwd = false);
              widget.onFwdUp();
            },
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          flex: 2,
          child: _hold(
            label: "▼ REV",
            active: _rev,
            base: AppTheme.kDim,
            activeFill: AppTheme.kRev,
            border: AppTheme.kRev,
            onDown: () {
              setState(() => _rev = true);
              widget.onRevDown();
            },
            onUp: () {
              setState(() => _rev = false);
              widget.onRevUp();
            },
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: widget.onStop,
            behavior: HitTestBehavior.opaque,
            child: ClippedCornerBox(
              cutSize: 5,
              backgroundColor: AppTheme.kStop,
              borderColor: AppTheme.kStop,
              topAccentColor: AppTheme.kStop,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Center(
                child: FittedBox(
                  child: Text(
                    "■ STOP",
                    style: AppTheme.labelUi(13, color: AppTheme.kTextPri, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hold({
    required String label,
    required bool active,
    required Color base,
    required Color activeFill,
    required Color border,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: ClippedCornerBox(
          cutSize: 5,
          backgroundColor: active ? activeFill.withValues(alpha: 0.35) : base,
          borderColor: border,
          topAccentColor: active ? activeFill : null,
          glowColor: active ? activeFill : null,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: FittedBox(
              child: Text(
                label,
                style: AppTheme.labelUi(12, color: active ? activeFill : AppTheme.kTextSec, weight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
