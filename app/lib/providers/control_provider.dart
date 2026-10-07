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

class _Latch {
  _Latch(this.value, this.command);

  final bool value;
  final Map<String, dynamic> command;
  final DateTime until = DateTime.now().add(const Duration(milliseconds: 1600));
  bool resent = false;
}

class ControlNotifier extends StateNotifier<ControlState> {
  _Latch? _enableLatch;
  _Latch? _autoLatch;
  _Latch? _navLatch;
  _Latch? _lightLatch;
  _Latch? _buzzLatch;

  ControlNotifier(this.ref, this.service) : super(ControlState.initial) {
    ref.listen(connectionProvider, (ConnectionUiState? _, ConnectionUiState next) {
      if (next.status == ConnectionStatus.connected) {
        _flushQueue();
      }
    });
    ref.listen(telemetryProvider, (AsyncValue<Telemetry>? _, AsyncValue<Telemetry> next) {
      next.whenData((Telemetry telemetry) {
        state = state.copyWith(
          auto: _apply(telemetry.auto, _autoLatch, (bool clear) => _autoLatch = clear ? null : _autoLatch),
          enabled: _apply(
            telemetry.enabled,
            _enableLatch,
            (bool clear) => _enableLatch = clear ? null : _enableLatch,
          ),
          navLeds: _apply(telemetry.navLeds, _navLatch, (bool clear) => _navLatch = clear ? null : _navLatch),
          headlight: _apply(
            telemetry.headlight,
            _lightLatch,
            (bool clear) => _lightLatch = clear ? null : _lightLatch,
          ),
          buzzerMuted: _apply(
            telemetry.buzzerMuted,
            _buzzLatch,
            (bool clear) => _buzzLatch = clear ? null : _buzzLatch,
          ),
        );
      });
    });
  }

  final Ref ref;
  final WebSocketService service;
  final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();

  bool _apply(bool telemetryValue, _Latch? latch, void Function(bool clear) write) {
    if (latch == null) {
      return telemetryValue;
    }
    if (telemetryValue == latch.value || DateTime.now().isAfter(latch.until)) {
      write(true);
      return telemetryValue == latch.value ? latch.value : telemetryValue;
    }
    final int ageMs = 1600 - latch.until.difference(DateTime.now()).inMilliseconds;
    if (!latch.resent && ageMs > 400) {
      latch.resent = true;
      service.send(latch.command);
    }
    return latch.value;
  }

  void sendCommand(Map<String, dynamic> command) {
    final String cmd = command["cmd"]?.toString() ?? "";
    if (cmd == "auto" && command["state"] is bool) {
      final bool value = command["state"] as bool;
      state = state.copyWith(auto: value);
      _autoLatch = _Latch(value, command);
    } else if (cmd == "enable" && command["state"] is bool) {
      final bool value = command["state"] as bool;
      state = state.copyWith(enabled: value);
      _enableLatch = _Latch(value, command);
    } else if (cmd == "leds") {
      if (command["nav"] is bool) {
        final bool value = command["nav"] as bool;
        state = state.copyWith(navLeds: value);
        _navLatch = _Latch(value, command);
      }
      if (command["headlight"] is bool) {
        final bool value = command["headlight"] as bool;
        state = state.copyWith(headlight: value);
        _lightLatch = _Latch(value, command);
      }
    } else if (cmd == "buzzer" && command["mute"] is bool) {
      final bool value = command["mute"] as bool;
      state = state.copyWith(buzzerMuted: value);
      _buzzLatch = _Latch(value, command);
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
