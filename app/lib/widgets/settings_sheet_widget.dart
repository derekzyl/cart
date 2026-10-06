import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../providers/connection_provider.dart";
import "../providers/settings_provider.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";
import "wifi_setup_sheet.dart";

class SettingsSheetWidget extends ConsumerStatefulWidget {
  const SettingsSheetWidget({super.key});

  @override
  ConsumerState<SettingsSheetWidget> createState() => _SettingsSheetWidgetState();
}

class _SettingsSheetWidgetState extends ConsumerState<SettingsSheetWidget> {
  late final TextEditingController _ipController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final ControlSettings s = ref.read(settingsProvider);
    _ipController = TextEditingController(text: s.ip);
    _portController = TextEditingController(text: s.port.toString());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ControlSettings settings = ref.watch(settingsProvider);
    return ClippedCornerBox(
      cutSize: 6,
      backgroundColor: AppTheme.kPanel,
      borderColor: AppTheme.kBorder,
      topAccentColor: AppTheme.kAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 32,
              height: 4,
              color: AppTheme.kAccent.withValues(alpha: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              "SYSTEM CONFIG",
              style: AppTheme.displayNum(13, color: AppTheme.kAccent),
            ),
          ),
          const Divider(height: 1, color: AppTheme.kBorder),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: <Widget>[
                Text("CONTROL", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        "Dead zone",
                        style: AppTheme.labelUi(11, color: AppTheme.kTextSec),
                      ),
                    ),
                    Text(
                      "${settings.deadZonePx.toStringAsFixed(0)} px",
                      style: AppTheme.monoData(11, color: AppTheme.kTextNum),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: AppTheme.kAccent,
                    inactiveTrackColor: AppTheme.kDim,
                    thumbColor: AppTheme.kAccent,
                    overlayColor: AppTheme.kAccent.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: settings.deadZonePx,
                    min: 5,
                    max: 40,
                    onChanged: (double v) =>
                        ref.read(settingsProvider.notifier).update(settings.copyWith(deadZonePx: v)),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        "Sensitivity",
                        style: AppTheme.labelUi(11, color: AppTheme.kTextSec),
                      ),
                    ),
                    Text(
                      settings.sensitivityOverride.toStringAsFixed(1),
                      style: AppTheme.monoData(11, color: AppTheme.kTextNum),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: AppTheme.kAccent,
                    inactiveTrackColor: AppTheme.kDim,
                    thumbColor: AppTheme.kAccent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: settings.sensitivityOverride,
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
                    onChanged: (double v) =>
                        ref.read(settingsProvider.notifier).update(settings.copyWith(sensitivityOverride: v)),
                  ),
                ),
                Text("Command rate", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (final int hz in <int>[10, 20, 30]) ...<Widget>[
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              ref.read(settingsProvider.notifier).update(settings.copyWith(commandRateHz: hz)),
                          child: ClippedCornerBox(
                            cutSize: 4,
                            backgroundColor:
                                settings.commandRateHz == hz ? AppTheme.kAccent.withValues(alpha: 0.15) : AppTheme.kDim,
                            borderColor: settings.commandRateHz == hz ? AppTheme.kAccent : AppTheme.kBorder,
                            topAccentColor: settings.commandRateHz == hz ? AppTheme.kAccent : null,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Text(
                                "${hz}Hz",
                                style: AppTheme.labelUi(11,
                                    color: settings.commandRateHz == hz ? AppTheme.kAccent : AppTheme.kTextSec),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (hz != 30) const SizedBox(width: 6),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppTheme.kBorder),
                const SizedBox(height: 12),
                Text("ROBOT WI-FI CONFIGURATION", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    WifiSetupSheet.show(context);
                  },
                  child: ClippedCornerBox(
                    cutSize: 5,
                    backgroundColor: AppTheme.kSurface,
                    borderColor: AppTheme.kAccent,
                    topAccentColor: AppTheme.kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.wifi_rounded, color: AppTheme.kAccent, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            "CONFIGURE WI-FI / SWITCH NETWORK",
                            style: AppTheme.labelUi(11, color: AppTheme.kAccent, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppTheme.kBorder),
                const SizedBox(height: 12),
                Text("NETWORK TARGET", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 8),
                ClippedCornerBox(
                  cutSize: 5,
                  backgroundColor: AppTheme.kSurface,
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextField(
                    controller: _ipController,
                    style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                    cursorColor: AppTheme.kTextPri,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: "IP",
                      labelStyle: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ClippedCornerBox(
                  cutSize: 5,
                  backgroundColor: AppTheme.kSurface,
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                    cursorColor: AppTheme.kTextPri,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: "Port",
                      labelStyle: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    final int port = int.tryParse(_portController.text.trim()) ?? settings.port;
                    ref.read(settingsProvider.notifier).update(
                          settings.copyWith(
                            ip: _ipController.text.trim().isEmpty ? settings.ip : _ipController.text.trim(),
                            port: port,
                          ),
                        );
                    final ControlSettings s = ref.read(settingsProvider);
                    ref.read(connectionProvider.notifier).connect(s.ip, s.port);
                  },
                  child: ClippedCornerBox(
                    cutSize: 5,
                    backgroundColor: AppTheme.kDim,
                    borderColor: AppTheme.kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        "RECONNECT",
                        style: AppTheme.labelUi(12, color: AppTheme.kAccent, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Nav LEDs default on connect",
                    style: AppTheme.labelUi(11, color: AppTheme.kTextSec),
                  ),
                  value: settings.defaultNavLedsOnConnect,
                  activeThumbColor: AppTheme.kAccent,
                  activeTrackColor: AppTheme.kAccent.withValues(alpha: 0.35),
                  onChanged: (bool value) =>
                      ref.read(settingsProvider.notifier).update(settings.copyWith(defaultNavLedsOnConnect: value)),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppTheme.kBorder),
                const SizedBox(height: 12),
                Text("DEFAULTS", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    await ref.read(settingsProvider.notifier).reset();
                    final ControlSettings s = ref.read(settingsProvider);
                    _ipController.text = s.ip;
                    _portController.text = s.port.toString();
                  },
                  child: ClippedCornerBox(
                    cutSize: 5,
                    backgroundColor: AppTheme.kStop.withValues(alpha: 0.12),
                    borderColor: AppTheme.kStop,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        "RESET ALL",
                        style: AppTheme.labelUi(12, color: AppTheme.kStop, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    final int port = int.tryParse(_portController.text.trim()) ?? settings.port;
                    ref.read(settingsProvider.notifier).update(
                          settings.copyWith(
                            ip: _ipController.text.trim().isEmpty ? settings.ip : _ipController.text.trim(),
                            port: port,
                          ),
                        );
                    Navigator.of(context).pop();
                  },
                  child: ClippedCornerBox(
                    cutSize: 6,
                    backgroundColor: AppTheme.kAccent.withValues(alpha: 0.12),
                    borderColor: AppTheme.kAccent,
                    topAccentColor: AppTheme.kAccent,
                    glowColor: AppTheme.kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        "APPLY & CLOSE",
                        style: AppTheme.labelUi(13, color: AppTheme.kAccent, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
