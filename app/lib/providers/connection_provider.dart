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
      if (status == SocketStatus.connecting) {
        _connectingSince = DateTime.now();
      }
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

    _retryLoop = Timer.periodic(const Duration(seconds: 3), (_) {
      if (service.currentStatus == SocketStatus.connected) {
        return;
      }
      if (service.currentStatus == SocketStatus.connecting &&
          DateTime.now().difference(_connectingSince) < const Duration(seconds: 8)) {
        return;
      }
      final ControlSettings s = ref.read(settingsProvider);
      unawaited(connect(s.ip, s.port, force: true));
    });

    _netSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool online = results.any(
        (ConnectivityResult r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet,
      );
      if (!online || service.currentStatus == SocketStatus.connected) {
        return;
      }
      _netRetry?.cancel();
      _netRetry = Timer(const Duration(milliseconds: 1000), () {
        if (service.currentStatus == SocketStatus.connected) {
          return;
        }
        final ControlSettings s = ref.read(settingsProvider);
        unawaited(connect(s.ip, s.port, force: true));
      });
    });
  }

  final Ref ref;
  final WebSocketService service;
  StreamSubscription<SocketStatus>? _statusSub;
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<int?>? _latencySub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _netRetry;
  Timer? _retryLoop;
  Future<void>? _inflight;
  int _attempt = 0;
  DateTime _connectingSince = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> connect(String host, int port, {bool force = false}) {
    final String h = host.trim();
    final bool sameTarget = state.host == h && state.port == port;
    final bool busy = service.currentStatus == SocketStatus.connecting ||
        service.currentStatus == SocketStatus.connected;
    if (!force && sameTarget && busy && _inflight != null) {
      return _inflight!;
    }
    final int attempt = ++_attempt;
    final Future<void> task = _open(h, port, attempt);
    _inflight = task;
    return task;
  }

  Future<void> _open(String host, int port, int attempt) async {
    state = state.copyWith(
      host: host,
      port: port,
      status: ConnectionStatus.connecting,
      clearError: true,
    );
    try {
      if (service.currentStatus != SocketStatus.disconnected) {
        await service.disconnect(publishStatus: false);
      }
      if (attempt != _attempt) {
        return;
      }
      await service.connect(host: host, port: port);
    } catch (e) {
      if (attempt != _attempt) {
        return;
      }
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        lastError: e.toString(),
      );
    } finally {
      if (attempt == _attempt) {
        _inflight = null;
      }
    }
  }

  @override
  void dispose() {
    _netRetry?.cancel();
    _retryLoop?.cancel();
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

