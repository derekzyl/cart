import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "shared/compact_toggle.dart";

class LedBuzzerControlsWidget extends StatefulWidget {
  const LedBuzzerControlsWidget({
    super.key,
    required this.navLeds,
    required this.headlight,
    required this.buzzerMuted,
    required this.onNavLeds,
    required this.onHeadlight,
    required this.onBuzzerMuted,
    required this.steeringActive,
  });

  final bool navLeds;
  final bool headlight;
  final bool buzzerMuted;
  final ValueChanged<bool> onNavLeds;
  final ValueChanged<bool> onHeadlight;
  final ValueChanged<bool> onBuzzerMuted;
  final bool steeringActive;

  @override
  State<LedBuzzerControlsWidget> createState() => _LedBuzzerControlsWidgetState();
}

class _LedBuzzerControlsWidgetState extends State<LedBuzzerControlsWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool blinkNav = widget.navLeds && widget.steeringActive;
    return AnimatedBuilder(
      animation: _blink,
      builder: (BuildContext context, Widget? _) {
        final bool navLit = widget.navLeds && (!blinkNav || _blink.value >= 0.5);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _tile(
                mark: "◄►",
                lit: navLit,
                label: "NAV",
                value: widget.navLeds,
                onChanged: widget.onNavLeds,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _tile(
                mark: "◎",
                lit: widget.headlight,
                label: "LIGHT",
                value: widget.headlight,
                onChanged: widget.onHeadlight,
                activeColor: AppTheme.kWarn,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _tile(
                mark: "♪",
                lit: !widget.buzzerMuted,
                label: "BUZZ",
                value: !widget.buzzerMuted,
                onChanged: (bool v) => widget.onBuzzerMuted(!v),
                activeColor: AppTheme.kAccent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tile({
    required String mark,
    required bool lit,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color activeColor = AppTheme.kGo,
  }) {
    return ClippedCornerBox(
      cutSize: 4,
      backgroundColor: AppTheme.kPanel,
      borderColor: value ? activeColor.withValues(alpha: 0.7) : AppTheme.kBorder,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: <Widget>[
          Text(
            mark,
            style: AppTheme.monoData(11, color: lit ? activeColor : AppTheme.kTextSec, weight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
            ),
          ),
          CompactToggle(value: value, onChanged: onChanged, activeColor: activeColor),
        ],
      ),
    );
  }

}
