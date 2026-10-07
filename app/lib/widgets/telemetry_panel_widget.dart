import "package:flutter/material.dart";

import "../core/telemetry_model.dart";
import "../theme/app_theme.dart";
import "drive_badge_widget.dart";
import "shared/clipped_corner_box.dart";
import "shared/data_chip.dart";
import "steering_bar_widget.dart";

class TelemetryPanelWidget extends StatelessWidget {
  const TelemetryPanelWidget({
    super.key,
    required this.telemetry,
  });

  final Telemetry telemetry;

  @override
  Widget build(BuildContext context) {
    double shown = telemetry.steerAngle % 360.0;
    if (shown < 0) {
      shown += 360.0;
    }
    if (shown > 180.0) {
      shown -= 360.0;
    }
    final int signedSteer = (shown / 180.0 * 255.0).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (telemetry.auto)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ClippedCornerBox(
              cutSize: 4,
              backgroundColor: AppTheme.kWarn.withValues(alpha: 0.15),
              borderColor: AppTheme.kWarn.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                "AUTO",
                textAlign: TextAlign.center,
                style: AppTheme.labelUi(10, color: AppTheme.kWarn, weight: FontWeight.w700),
              ),
            ),
          ),
        _distanceRow(telemetry.distCm),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DriveBadgeWidget(drive: telemetry.drive),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(flex: 3, child: SteeringBarWidget(pwm: signedSteer)),
              const SizedBox(width: 4),
              SizedBox(
                width: 62,
                child: DataChip(
                  label: "SENS",
                  value: telemetry.sensitivity.toStringAsFixed(1),
                ),
              ),
              const SizedBox(width: 4),
              _btnDots(telemetry.btn1, telemetry.btn2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _distanceRow(int cm) {
    final bool live = cm >= 0;
    final Color tone = !live
        ? AppTheme.kTextSec
        : cm < 25
            ? AppTheme.kStop
            : cm < 60
                ? AppTheme.kWarn
                : AppTheme.kGo;
    return ClippedCornerBox(
      cutSize: 4,
      backgroundColor: AppTheme.kPanel,
      borderColor: tone.withValues(alpha: live ? 0.8 : 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: <Widget>[
          Text("DIST", style: AppTheme.labelUi(10, color: AppTheme.kTextSec, weight: FontWeight.w700)),
          const Spacer(),
          Text(
            live ? "$cm cm" : "no echo",
            style: AppTheme.displayNum(16, color: tone),
          ),
        ],
      ),
    );
  }

  Widget _btnDots(bool b1, bool b2) {
    return ClippedCornerBox(
      cutSize: 4,
      backgroundColor: AppTheme.kPanel,
      borderColor: AppTheme.kBorder,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text("BTN", style: AppTheme.labelUi(8, color: AppTheme.kTextSec)),
            const SizedBox(width: 3),
            _dot(b1),
            const SizedBox(width: 3),
            _dot(b2),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool on) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: on ? AppTheme.kGo : AppTheme.kDim,
        border: Border.all(color: on ? AppTheme.kGo : AppTheme.kBorder),
      ),
    );
  }
}
