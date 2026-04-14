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
      ControlState(auto: false, enabled: false, navLeds: true, headlight: false, buzzerMuted: false);
}

class ControlNotifier extends StateNotifier<ControlState> {
  ControlNotifier(this.ref, this.service) : super(ControlState.initial) {
    ref.listen(connectionProvider, (ConnectionUiState? _, ConnectionUiState next) {
      if (next.status == ConnectionStatus.connected) {
        _flushQueue();
        // Do not push defaultNavLedsOnConnect here — it overwrote the user's nav toggle
        // every reconnect. Firmware keeps LED state; telemetry syncs the UI.
      }
    });
    ref.listen(telemetryProvider, (AsyncValue<Telemetry>? _, AsyncValue<Telemetry> next) {
      next.whenData((Telemetry telemetry) {
        state = state.copyWith(
          auto: telemetry.auto,
          enabled: telemetry.enabled,
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
