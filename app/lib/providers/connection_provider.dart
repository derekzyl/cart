import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/websocket_service.dart";
import "settings_provider.dart";

enum ConnectionStatus { disconnected, connecting, connected }

class ConnectionUiState {
  const ConnectionUiState({
    required this.status,
    required this.lastError,
    required this.host,
    required this.port,
    required this.latencyMs,
  });

  final ConnectionStatus status;
  final String? lastError;
  final String host;
  final int port;
  final int? latencyMs;

  ConnectionUiState copyWith({
    ConnectionStatus? status,
    String? lastError,
    String? host,
    int? port,
    int? latencyMs,
    bool clearError = false,
  }) {
    return ConnectionUiState(
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
      host: host ?? this.host,
      port: port ?? this.port,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

class ConnectionNotifier extends StateNotifier<ConnectionUiState> {
  ConnectionNotifier(this.ref, this.service)
      : super(const ConnectionUiState(
          status: ConnectionStatus.disconnected,
          lastError: null,
          host: "192.168.4.1",
          port: 8080,
          latencyMs: null,
        )) {
    _statusSub = service.statuses.listen((SocketStatus status) {
      state = state.copyWith(
        status: switch (status) {
          SocketStatus.connected => ConnectionStatus.connected,
          SocketStatus.connecting => ConnectionStatus.connecting,
          SocketStatus.disconnected => ConnectionStatus.disconnected,
        },
      );
    });
    _errorSub = service.errors.listen((String? error) {
      if (error == null || error.isEmpty) {
        state = state.copyWith(clearError: true);
        return;
      }
      state = state.copyWith(lastError: error);
    });
    _latencySub = service.latencyMs.listen((int? latency) {
      state = state.copyWith(latencyMs: latency);
    });
    final ControlSettings settings = ref.read(settingsProvider);
    state = state.copyWith(host: settings.ip, port: settings.port);
    ref.listen<ControlSettings>(settingsProvider, (ControlSettings? previous, ControlSettings next) {
      final bool changed = next.ip != state.host || next.port != state.port;
      if (!changed) {
        return;
      }
      state = state.copyWith(host: next.ip, port: next.port);
      final bool alreadyConnectedToTarget =
          service.currentStatus == SocketStatus.connected &&
          state.host == next.ip &&
          state.port == next.port;
      if (!alreadyConnectedToTarget) {
        unawaited(connect(next.ip, next.port));
      }
    });
    unawaited(connect(settings.ip, settings.port));

    _netSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool online = results.any(
        (ConnectivityResult r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet,
      );
      if (!online) {
        return;
      }
      if (state.status != ConnectionStatus.disconnected) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        final ControlSettings s = ref.read(settingsProvider);
        unawaited(connect(s.ip, s.port));
      });
    });
  }

  final Ref ref;
  final WebSocketService service;
  StreamSubscription<SocketStatus>? _statusSub;
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<int?>? _latencySub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  Future<void> connect(String host, int port) async {
    final String h = host.trim();
    state = state.copyWith(
      host: h,
      port: port,
      status: ConnectionStatus.connecting,
      clearError: true,
    );
    try {
      await service.disconnect(publishStatus: false);
      await service.connect(host: h, port: port);
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        lastError: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _errorSub?.cancel();
    _latencySub?.cancel();
    _netSub?.cancel();
    super.dispose();
  }
}

final Provider<WebSocketService> websocketServiceProvider = Provider<WebSocketService>((Ref ref) {
  final WebSocketService service = WebSocketService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final StateNotifierProvider<ConnectionNotifier, ConnectionUiState> connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionUiState>((Ref ref) {
  return ConnectionNotifier(ref, ref.watch(websocketServiceProvider));
});

