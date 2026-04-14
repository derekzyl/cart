import "package:flutter/material.dart";

import "../../theme/app_theme.dart";
import "clipped_corner_box.dart";

/// Compact readout: label + value (fixed height 24px).
class DataChip extends StatelessWidget {
  const DataChip({
    super.key,
    required this.label,
    required this.value,
    this.flex,
  });

  final String label;
  final String value;
  final int? flex;

  @override
  Widget build(BuildContext context) {
    final Widget inner = SizedBox(
      height: 24,
      child: ClippedCornerBox(
        cutSize: 4,
        backgroundColor: AppTheme.kPanel,
        borderColor: AppTheme.kBorder,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: AppTheme.labelUi(9, color: AppTheme.kTextSec),
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  style: AppTheme.monoData(11, color: AppTheme.kTextNum),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (flex != null) {
      return Expanded(flex: flex!, child: inner);
    }
    return inner;
  }
}
