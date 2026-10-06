import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/telemetry_model.dart";
import "connection_provider.dart";
import "telemetry_provider.dart";

class RouteUiState {
  const RouteUiState({
    required this.state,
    required this.step,
    required this.total,
    required this.interrupted,
    this.activeName = "",
    this.savedNames = const <String>[],
  });

  final RouteState state;
  final int step;
  final int total;
  final bool interrupted;
  final String activeName;
  final List<String> savedNames;

  bool get canRecord => state == RouteState.idle;
  bool get canPlay => state == RouteState.idle && total > 0;
  bool get canReturn => state == RouteState.idle && total > 0;
  bool get canStop =>
      state == RouteState.recording || state == RouteState.playing || state == RouteState.playingReverse;

  /// Clear stored route when idle and something was recorded.
  bool get canClearMemory => state == RouteState.idle && total > 0;

  RouteUiState copyWith({
    RouteState? state,
    int? step,
    int? total,
    bool? interrupted,
    String? activeName,
    List<String>? savedNames,
  }) {
    return RouteUiState(
      state: state ?? this.state,
      step: step ?? this.step,
      total: total ?? this.total,
      interrupted: interrupted ?? this.interrupted,
      activeName: activeName ?? this.activeName,
      savedNames: savedNames ?? this.savedNames,
    );
  }

  static const RouteUiState initial =
      RouteUiState(state: RouteState.idle, step: 0, total: 0, interrupted: false);
}

class RouteNotifier extends StateNotifier<RouteUiState> {
  RouteNotifier(this.ref) : super(RouteUiState.initial) {
    ref.listen(connectionProvider, (ConnectionUiState? prev, ConnectionUiState next) {
      if (next.status != ConnectionStatus.connected) {
        final bool interrupted = state.state == RouteState.playing || state.state == RouteState.playingReverse;
        state = RouteUiState.initial.copyWith(interrupted: interrupted);
      } else {
        state = state.copyWith(interrupted: false);
      }
    });
    ref.listen(telemetryProvider, (AsyncValue<Telemetry>? _, AsyncValue<Telemetry> next) {
      next.whenData((Telemetry telemetry) {
        final List<String> names = telemetry.routeNames
            .split("|")
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
        state = state.copyWith(
          state: telemetry.routeState,
          step: telemetry.routeStep,
          total: telemetry.routeTotal,
          activeName: telemetry.routeName,
          savedNames: names,
        );
      });
    });
  }

  final Ref ref;

  void clearInterrupted() {
    state = state.copyWith(interrupted: false);
  }
}

final StateNotifierProvider<RouteNotifier, RouteUiState> routeProvider =
    StateNotifierProvider<RouteNotifier, RouteUiState>((Ref ref) => RouteNotifier(ref));

