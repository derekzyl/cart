import "package:flutter/material.dart";

import "../core/telemetry_model.dart";
import "../providers/route_provider.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "shared/panel_label.dart";

class RoutePanelWidget extends StatefulWidget {
  const RoutePanelWidget({
    super.key,
    required this.state,
    required this.onRecordToggle,
    required this.onPlayback,
    required this.onReturn,
    required this.onStop,
    required this.onClearMemory,
  });

  final RouteUiState state;
  final VoidCallback onRecordToggle;
  final VoidCallback onPlayback;
  final VoidCallback onReturn;
  final VoidCallback onStop;
  final VoidCallback onClearMemory;

  @override
  State<RoutePanelWidget> createState() => _RoutePanelWidgetState();
}

class _RoutePanelWidgetState extends State<RoutePanelWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _recPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _recPulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RoutePanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool rec = widget.state.state == RouteState.recording;
    if (rec) {
      _recPulse.repeat(reverse: true);
    } else {
      _recPulse.stop();
      _recPulse.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.state.state == RouteState.recording) {
      _recPulse.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final RouteUiState s = widget.state;
    final bool playing = s.state == RouteState.playing || s.state == RouteState.playingReverse;
    final double progress = s.total <= 0 ? 0 : (s.step / s.total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelLabel("ROUTE MEMORY"),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _stateBadge(s),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          "${s.step} / ${s.total}",
                          style: AppTheme.monoData(11, color: AppTheme.kTextNum),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints bc) {
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        const ColoredBox(color: AppTheme.kDim),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          width: playing ? bc.maxWidth * progress : 0,
                          color: s.state == RouteState.playingReverse ? AppTheme.kRev : AppTheme.kGo,
                          alignment: Alignment.centerLeft,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 3,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(child: _gridBtn(s.state == RouteState.recording ? "STOP REC" : "RECORD", s.canRecord || s.state == RouteState.recording, AppTheme.kRecord, widget.onRecordToggle)),
                          const SizedBox(width: 4),
                          Expanded(child: _gridBtn("STOP", s.canStop, AppTheme.kStop, widget.onStop)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(child: _gridBtn("PLAY", s.canPlay, AppTheme.kGo, widget.onPlayback)),
                          const SizedBox(width: 4),
                          Expanded(child: _gridBtn("RETURN", s.canReturn, AppTheme.kRev, widget.onReturn)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: _gridBtn(
                        "CLEAR ROUTE",
                        s.canClearMemory,
                        AppTheme.kStop,
                        widget.onClearMemory,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.interrupted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FittedBox(
                    child: Text(
                      "Route interrupted — reconnecting",
                      style: AppTheme.monoData(9, color: AppTheme.kStop),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stateBadge(RouteUiState s) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(a), child: child),
      ),
      child: switch (s.state) {
        RouteState.idle => _badgeKey(
            "idle",
            AppTheme.kDim,
            AppTheme.kBorder,
            "IDLE",
            AppTheme.kTextSec,
            false,
          ),
        RouteState.recording => AnimatedBuilder(
            key: const ValueKey<String>("rec"),
            animation: _recPulse,
            builder: (BuildContext context, Widget? _) {
              final double op = 0.35 + _recPulse.value * 0.65;
              return Opacity(
                opacity: op,
                child: _badgeKey(
                  "rec",
                  AppTheme.kRecord.withValues(alpha: 0.2),
                  AppTheme.kRecord,
                  "● REC",
                  AppTheme.kRecord,
                  true,
                ),
              );
            },
          ),
        RouteState.playing => _badgeKey(
            "play",
            AppTheme.kGo.withValues(alpha: 0.18),
            AppTheme.kGo,
            "▶ PLAY",
            AppTheme.kGo,
            true,
          ),
        RouteState.playingReverse => _badgeKey(
            "rtn",
            AppTheme.kRev.withValues(alpha: 0.18),
            AppTheme.kRev,
            "◀ RTN",
            AppTheme.kRev,
            true,
          ),
      },
    );
  }

  Widget _badgeKey(
    String key,
    Color bg,
    Color border,
    String text,
    Color fg,
    bool accent,
  ) {
    return ClippedCornerBox(
      key: ValueKey<String>(key),
      cutSize: 5,
      backgroundColor: bg,
      borderColor: border,
      topAccentColor: accent ? border : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Center(
        child: FittedBox(
          child: Text(text, style: AppTheme.labelUi(11, color: fg, weight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _gridBtn(String label, bool enabled, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: ClippedCornerBox(
          cutSize: 4,
          backgroundColor: enabled ? c.withValues(alpha: 0.12) : AppTheme.kDim,
          borderColor: enabled ? c : AppTheme.kBorder,
          topAccentColor: enabled ? c : null,
          glowColor: enabled ? c : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Center(
            child: FittedBox(
              child: Text(
                label,
                style: AppTheme.labelUi(11, color: enabled ? c : AppTheme.kTextSec, weight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
