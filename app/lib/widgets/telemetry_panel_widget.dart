import "package:flutter/material.dart";

import "../core/telemetry_model.dart";
import "../theme/app_theme.dart";
import "arc_gauge_widget.dart";
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
    final int signedSteer = switch (telemetry.drive) {
      DriveState.fwd => telemetry.steerPwm,
      DriveState.rev => -telemetry.steerPwm,
      DriveState.stop => 0,
    };
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              height: telemetry.auto ? 20 : 0,
              child: telemetry.auto
                  ? ClippedCornerBox(
                      cutSize: 4,
                      backgroundColor: AppTheme.kWarn.withValues(alpha: 0.15),
                      borderColor: AppTheme.kWarn.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Center(
                        child: FittedBox(
                          child: Text(
                            "◈ AUTO MODE ACTIVE",
                            style: AppTheme.labelUi(10, color: AppTheme.kWarn, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              flex: 5,
              child: ArcGaugeWidget(distanceCm: telemetry.distCm),
            ),
            Expanded(
              flex: 2,
              child: Center(child: DriveBadgeWidget(drive: telemetry.drive)),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: DataChip(
                            label: "SENS",
                            value: telemetry.sensitivity.toStringAsFixed(1),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Text("STR", style: AppTheme.labelUi(9, color: AppTheme.kTextSec)),
                              ),
                              Expanded(child: SteeringBarWidget(pwm: signedSteer)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _btnDots(telemetry.btn1, telemetry.btn2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
