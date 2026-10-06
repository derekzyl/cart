import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:web_socket_channel/web_socket_channel.dart";

enum SocketStatus { disconnected, connecting, connected }

class WebSocketService {
  WebSocketService();

  void _log(String msg) {
    debugPrint("[WS-APP] $msg");
  }

  Future<List<String>> _logLocalNetworkState() async {
    final List<String> ipsOut = <String>[];
    try {
      final List<NetworkInterface> ifaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      if (ifaces.isEmpty) {
        _log("local-iface none");
        return ipsOut;
      }
      for (final NetworkInterface iface in ifaces) {
        final String ips =
            iface.addresses.map((InternetAddress a) => a.address).join(",");
        ipsOut.addAll(iface.addresses.map((InternetAddress a) => a.address));
        _log("local-iface ${iface.name}: $ips");
      }
    } catch (e) {
      _log("local-iface read failed: $e");
    }
    return ipsOut;
  }

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<SocketStatus> _statusController =
      StreamController<SocketStatus>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final StreamController<int?> _latencyController =
      StreamController<int?>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  DateTime? _lastPingSent;
  bool _manualDisconnect = false;
  int _reconnectSeconds = 2;
  String _host = "192.168.4.1";
  int _port = 8080;
  DateTime _lastRx = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _isNetworkUnreachable(Object? e) {
    if (e == null) return false;
    if (e is SocketException) {
      return e.osError?.errorCode == 101 || (e.message.contains("Network is unreachable"));
    }
    if (e is WebSocketChannelException) {
      return _isNetworkUnreachable(e.inner);
    }
    return false;
  }

  Stream<String> get messages => _messageController.stream;
  Stream<SocketStatus> get statuses => _statusController.stream;
  Stream<String?> get errors => _errorController.stream;
  Stream<int?> get latencyMs => _latencyController.stream;
  SocketStatus currentStatus = SocketStatus.disconnected;

  Future<void> connect({required String host, required int port}) async {
    _host = host.trim();
    _port = port;
    _manualDisconnect = false;
    _reconnectSeconds = 2;
    _reconnectTimer?.cancel();
    await _cleanupChannel();
    _log("connect requested host=$_host port=$_port");
    // Android often returns no interfaces to untrusted apps. That is not proof
    // the phone is off the robot hotspot, so never abort the connection here.
    unawaited(_logLocalNetworkState());
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_manualDisconnect) return;
    _setStatus(SocketStatus.connecting);
    final List<Uri> candidates = <Uri>[
      Uri.parse("ws://$_host:$_port/ws"),
      Uri.parse("ws://$_host:$_port/"),
    ];
    try {
      await _cleanupChannel();
      Object? lastError;
      String? lastProbedHost;
      for (final Uri uri in candidates) {
        if (_manualDisconnect) return;
        if (lastProbedHost != uri.host) {
          lastProbedHost = uri.host;
          await _probeHealth(uri.host, uri.port);
        }
        _log("trying ${uri.toString()}");
        _errorController.add("Connecting ${uri.host}:${uri.port}${uri.path}…");
        try {
          final WebSocketChannel channel = WebSocketChannel.connect(uri);
          _channel = channel;
          await channel.ready.timeout(
            const Duration(seconds: 6),
            onTimeout: () =>
                throw TimeoutException("No response from ${uri.host}:${uri.port}${uri.path}"),
          );
          _sub = channel.stream.listen(
            _handleMessage,
            onDone: _handleDisconnect,
            onError: (Object e, StackTrace st) => _handleError(e),
            cancelOnError: true,
          );
          _log("connected ${uri.toString()}");
          _lastRx = DateTime.now();
          _setStatus(SocketStatus.connected);
          _errorController.add(null);
          _startPing();
          _reconnectSeconds = 2;
          return;
        } catch (e) {
          _log("failed ${uri.toString()} reason=$e");
          lastError = e;
          try {
            await _channel?.sink.close();
          } catch (_) {}
          _channel = null;
        }
      }
      throw lastError ?? TimeoutException("Could not reach robot at $_host or 192.168.4.1");
    } on TimeoutException catch (e) {
      _log("connect timeout $e");
      _handleError(e);
    } on WebSocketChannelException catch (e) {
      // Happens on TCP connection refused (robot AP not up yet) or wrong IP.
      _log("connect ws exception $e");
      _handleError(e);
    } on SocketException catch (e) {
      _log("connect socket exception $e");
      _handleError(e);
    } catch (e) {
      _log("connect unknown exception $e");
      _handleError(e);
    }
  }

  void _bumpBackoffIfUnreachable(Object e) {
    if (_isNetworkUnreachable(e)) {
      _reconnectSeconds = 3;
      _log("network unreachable — retry in ${_reconnectSeconds}s");
    }
  }

  Future<void> _probeHealth(String host, int port) async {
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final Uri uri = Uri.parse("http://$host:$port/health");
      final HttpClientRequest req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, "application/json");
      final HttpClientResponse res =
          await req.close().timeout(const Duration(seconds: 3));
      final String body = await utf8.decoder.bind(res).join();
      final String preview =
          body.length > 180 ? "${body.substring(0, 180)}..." : body;
      _log("health ${uri.toString()} -> ${res.statusCode} ${res.reasonPhrase}; $preview");
    } catch (e) {
      _log("health http://$host:$port/health failed: $e");
    } finally {
      client.close(force: true);
    }
  }

  void _handleMessage(dynamic data) {
    final String msg = data?.toString() ?? "";
    if (msg.isEmpty) return;
    _lastRx = DateTime.now();
    if (msg.contains('"pong"') || msg.length < 48) {
      _log("rx: $msg");
    }
    _messageController.add(msg);
    try {
      final dynamic decoded = jsonDecode(msg);
      if (decoded is Map<String, dynamic> &&
          decoded["cmd"] == "pong" &&
          _lastPingSent != null) {
        final int latency =
            DateTime.now().difference(_lastPingSent!).inMilliseconds;
        _latencyController.add(latency);
      }
    } catch (_) {}
  }

  void send(Map<String, dynamic> command) {
    if (currentStatus != SocketStatus.connected || _channel == null) return;
    try {
      _log("tx: ${jsonEncode(command)}");
      _channel!.sink.add(jsonEncode(command));
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _lastRx = DateTime.now();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (currentStatus != SocketStatus.connected) return;
      if (DateTime.now().difference(_lastRx) > const Duration(seconds: 6)) {
        _log("no data from robot for 6s — reconnecting");
        _handleDisconnect();
        return;
      }
      _lastPingSent = DateTime.now();
      send(<String, dynamic>{"cmd": "ping"});
    });
  }

  void _setStatus(SocketStatus status) {
    currentStatus = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _handleError(Object error) {
    _bumpBackoffIfUnreachable(error);
    String message;
    if (error is SocketException) {
      message = "Network error: ${error.message}";
    } else if (error is TimeoutException) {
      message = error.message ?? "Connection timed out";
    } else if (error is WebSocketChannelException) {
      final inner = error.inner;
      if (inner is SocketException) {
        message = "Can't reach robot: ${inner.message}";
      } else {
        message = "WebSocket error — check IP & that robot hotspot is active";
      }
    } else {
      final s = error.toString();
      message = s.isNotEmpty ? s : "Unknown connection error";
    }
    if (!_errorController.isClosed) _errorController.add(message);
    _log("error: $message");
    _handleDisconnect();
  }

  void _handleDisconnect() {
    unawaited(_handleDisconnectAsync());
  }

  Future<void> _cleanupChannel() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (_) {}
      _channel = null;
    }
  }

  Future<void> _handleDisconnectAsync() async {
    await _cleanupChannel();
    _setStatus(SocketStatus.disconnected);
    if (!_latencyController.isClosed) _latencyController.add(null);
    if (_manualDisconnect) return;

    _reconnectTimer?.cancel();
    final int wait = _reconnectSeconds.clamp(2, 8);
    _log("disconnected, retry in ${wait}s");
    if (!_errorController.isClosed) {
      _errorController.add(
        "Disconnected. Reconnecting in ${wait}s…\n"
        "(Join CartRobot_Setup WiFi or same LAN as the robot.)",
      );
    }
    _reconnectTimer = Timer(Duration(seconds: wait), () {
      unawaited(_connectInternal());
    });
    _reconnectSeconds = (_reconnectSeconds * 2).clamp(2, 8);
  }

  /// Tear down socket. Use [publishStatus] false when immediately calling [connect] again
  /// so the UI does not flash to disconnected.
  Future<void> disconnect({bool publishStatus = true}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    final bool hadSocket = _channel != null || _sub != null;
    if (hadSocket) {
      _log("manual disconnect");
    }
    await _cleanupChannel();
    if (publishStatus) {
      _setStatus(SocketStatus.disconnected);
      if (!_latencyController.isClosed) _latencyController.add(null);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _statusController.close();
    await _errorController.close();
    await _latencyController.close();
  }
}
