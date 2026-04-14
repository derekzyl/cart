import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

class ControlSettings {
  const ControlSettings({
    required this.deadZonePx,
    required this.sensitivityOverride,
    required this.commandRateHz,
    required this.ip,
    required this.port,
    required this.defaultNavLedsOnConnect,
  });

  final double deadZonePx;
  final double sensitivityOverride;
  final int commandRateHz;
  final String ip;
  final int port;
  final bool defaultNavLedsOnConnect;

  ControlSettings copyWith({
    double? deadZonePx,
    double? sensitivityOverride,
    int? commandRateHz,
    String? ip,
    int? port,
    bool? defaultNavLedsOnConnect,
  }) {
    return ControlSettings(
      deadZonePx: deadZonePx ?? this.deadZonePx,
      sensitivityOverride: sensitivityOverride ?? this.sensitivityOverride,
      commandRateHz: commandRateHz ?? this.commandRateHz,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      defaultNavLedsOnConnect: defaultNavLedsOnConnect ?? this.defaultNavLedsOnConnect,
    );
  }

  static const ControlSettings defaults = ControlSettings(
    deadZonePx: 18,
    sensitivityOverride: 1.0,
    commandRateHz: 20,
    ip: "192.168.4.1",
    port: 8080,
    defaultNavLedsOnConnect: true,
  );
}

class SettingsNotifier extends StateNotifier<ControlSettings> {
  SettingsNotifier() : super(ControlSettings.defaults) {
    unawaited(_load());
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      deadZonePx: _prefs!.getDouble("deadZonePx") ?? ControlSettings.defaults.deadZonePx,
      sensitivityOverride:
          _prefs!.getDouble("sensitivityOverride") ?? ControlSettings.defaults.sensitivityOverride,
      commandRateHz: _prefs!.getInt("commandRateHz") ?? ControlSettings.defaults.commandRateHz,
      ip: _prefs!.getString("ip") ?? ControlSettings.defaults.ip,
      port: _prefs!.getInt("port") ?? ControlSettings.defaults.port,
      defaultNavLedsOnConnect:
          _prefs!.getBool("defaultNavLedsOnConnect") ?? ControlSettings.defaults.defaultNavLedsOnConnect,
    );
  }

  Future<void> update(ControlSettings next) async {
    state = next;
    final SharedPreferences prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setDouble("deadZonePx", next.deadZonePx);
    await prefs.setDouble("sensitivityOverride", next.sensitivityOverride);
    await prefs.setInt("commandRateHz", next.commandRateHz);
    await prefs.setString("ip", next.ip);
    await prefs.setInt("port", next.port);
    await prefs.setBool("defaultNavLedsOnConnect", next.defaultNavLedsOnConnect);
  }

  Future<void> reset() => update(ControlSettings.defaults);
}

final StateNotifierProvider<SettingsNotifier, ControlSettings> settingsProvider =
    StateNotifierProvider<SettingsNotifier, ControlSettings>((Ref ref) => SettingsNotifier());
