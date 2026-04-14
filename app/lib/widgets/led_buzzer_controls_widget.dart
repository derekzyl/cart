import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "shared/compact_toggle.dart";
import "shared/panel_label.dart";

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelLabel("SYSTEMS"),
        Expanded(
          child: AnimatedBuilder(
            animation: _blink,
            builder: (BuildContext context, Widget? _) {
              final bool leftOn = blinkNav && _blink.value < 0.5;
              final bool rightOn = blinkNav && _blink.value >= 0.5;
              return Column(
                children: <Widget>[
                  Expanded(
                    child: _row(
                      iconL: "◄",
                      iconR: "►",
                      leftLit: leftOn,
                      rightLit: rightOn,
                      label: "NAV LEDS",
                      value: widget.navLeds,
                      onChanged: widget.onNavLeds,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _row(
                      iconL: "◎",
                      iconR: "",
                      leftLit: widget.headlight,
                      rightLit: false,
                      label: "HEADLIGHT",
                      value: widget.headlight,
                      onChanged: widget.onHeadlight,
                      headlightGlow: widget.headlight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _row(
                      iconL: "♪",
                      iconR: "",
                      leftLit: widget.buzzerMuted,
                      rightLit: false,
                      label: "BUZZER",
                      value: !widget.buzzerMuted,
                      onChanged: (bool v) => widget.onBuzzerMuted(!v),
                      activeColor: AppTheme.kAccent,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row({
    required String iconL,
    required String iconR,
    required bool leftLit,
    required bool rightLit,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool headlightGlow = false,
    Color activeColor = AppTheme.kGo,
  }) {
    return ClippedCornerBox(
      cutSize: 4,
      backgroundColor: AppTheme.kPanel,
      borderColor: AppTheme.kBorder,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  iconL,
                  style: AppTheme.monoData(11,
                      color: leftLit ? AppTheme.kAccent : AppTheme.kTextSec,
                      weight: FontWeight.w700),
                ),
                if (iconR.isNotEmpty)
                  Text(
                    iconR,
                    style: AppTheme.monoData(11,
                        color: rightLit ? AppTheme.kAccent : AppTheme.kTextSec,
                        weight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
              ),
            ),
          ),
          CompactToggle(
            value: value,
            onChanged: onChanged,
            activeColor: headlightGlow ? AppTheme.kWarn : activeColor,
          ),
        ],
      ),
    );
  }
}
