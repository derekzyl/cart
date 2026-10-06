import "dart:collection";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:vibration/vibration.dart";

import "../core/telemetry_model.dart";
import "../core/websocket_service.dart";
import "connection_provider.dart";
import "telemetry_provider.dart";

class ControlState {
  const ControlState({
    required this.auto,
    required this.enabled,
    required this.navLeds,
    required this.headlight,
    required this.buzzerMuted,
  });

  final bool auto;
  final bool enabled;
  final bool navLeds;
  final bool headlight;
  final bool buzzerMuted;

  ControlState copyWith({
    bool? auto,
    bool? enabled,
    bool? navLeds,
    bool? headlight,
    bool? buzzerMuted,
  }) {
    return ControlState(
      auto: auto ?? this.auto,
      enabled: enabled ?? this.enabled,
      navLeds: navLeds ?? this.navLeds,
      headlight: headlight ?? this.headlight,
      buzzerMuted: buzzerMuted ?? this.buzzerMuted,
    );
  }

  static const ControlState initial =
      ControlState(auto: false, enabled: false, navLeds: false, headlight: false, buzzerMuted: false);
}

class ControlNotifier extends StateNotifier<ControlState> {
  DateTime? _manualEnableUntil;
  DateTime? _manualAutoUntil;

  ControlNotifier(this.ref, this.service) : super(ControlState.initial) {
    ref.listen(connectionProvider, (ConnectionUiState? _, ConnectionUiState next) {
      if (next.status == ConnectionStatus.connected) {
        _flushQueue();
      }
    });
    ref.listen(telemetryProvider, (AsyncValue<Telemetry>? _, AsyncValue<Telemetry> next) {
      next.whenData((Telemetry telemetry) {
        final DateTime now = DateTime.now();
        final bool canUpdateEnable =
            _manualEnableUntil == null || now.isAfter(_manualEnableUntil!);
        final bool canUpdateAuto =
            _manualAutoUntil == null || now.isAfter(_manualAutoUntil!);
        state = state.copyWith(
          auto: canUpdateAuto ? telemetry.auto : state.auto,
          enabled: canUpdateEnable ? telemetry.enabled : state.enabled,
          navLeds: telemetry.navLeds,
          headlight: telemetry.headlight,
          buzzerMuted: telemetry.buzzerMuted,
        );
      });
    });
  }

  final Ref ref;
  final WebSocketService service;
  final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();

  void sendCommand(Map<String, dynamic> command) {
    if (command["cmd"] == "auto" && command["state"] is bool) {
      state = state.copyWith(auto: command["state"] as bool);
      _manualAutoUntil = DateTime.now().add(const Duration(milliseconds: 600));
    } else if (command["cmd"] == "enable" && command["state"] is bool) {
      state = state.copyWith(enabled: command["state"] as bool);
      _manualEnableUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    final ConnectionUiState connection = ref.read(connectionProvider);
    if (connection.status != ConnectionStatus.connected) {
      _queue.add(command);
      return;
    }
    service.send(command);
  }

  void _flushQueue() {
    while (_queue.isNotEmpty) {
      service.send(_queue.removeFirst());
    }
  }

  Future<void> heavyHaptic() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 20, amplitude: 180);
    }
  }

  Future<void> lightHaptic() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 12, amplitude: 100);
    }
  }
}

final StateNotifierProvider<ControlNotifier, ControlState> controlProvider =
    StateNotifierProvider<ControlNotifier, ControlState>((Ref ref) {
  return ControlNotifier(ref, ref.watch(websocketServiceProvider));
});
