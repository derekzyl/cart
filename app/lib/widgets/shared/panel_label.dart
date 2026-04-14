import "package:flutter/material.dart";

import "../../theme/app_theme.dart";

class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          color: AppTheme.kAccent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text.toUpperCase(),
              style: AppTheme.labelUi(9, color: AppTheme.kTextSec).copyWith(letterSpacing: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
