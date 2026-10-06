import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/robot_commands.dart";
import "../core/websocket_service.dart";
import "connection_provider.dart";
import "settings_provider.dart";

class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  final String ssid;
  final int rssi;
  final bool secure;

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: "${json["ssid"] ?? ""}",
      rssi: (json["rssi"] is num) ? (json["rssi"] as num).toInt() : -99,
      secure: json["secure"] == true,
    );
  }
}

enum WifiConfigStatus { idle, scanning, connecting, connected, failed, reset }

class WifiState {
  const WifiState({
    this.status = WifiConfigStatus.idle,
    this.availableNetworks = const <WifiNetwork>[],
    this.newIp,
    this.activeSsid,
    this.activeMode = "ap",
    this.errorMessage,
  });

  final WifiConfigStatus status;
  final List<WifiNetwork> availableNetworks;
  final String? newIp;
  final String? activeSsid;
  final String activeMode;
  final String? errorMessage;

  WifiState copyWith({
    WifiConfigStatus? status,
    List<WifiNetwork>? availableNetworks,
    String? newIp,
    String? activeSsid,
    String? activeMode,
    String? errorMessage,
    bool clearError = false,
    bool clearNewIp = false,
  }) {
    return WifiState(
      status: status ?? this.status,
      availableNetworks: availableNetworks ?? this.availableNetworks,
      newIp: clearNewIp ? null : (newIp ?? this.newIp),
      activeSsid: activeSsid ?? this.activeSsid,
      activeMode: activeMode ?? this.activeMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class WifiNotifier extends StateNotifier<WifiState> {
  WifiNotifier(this.ref) : super(const WifiState()) {
    final WebSocketService service = ref.read(websocketServiceProvider);
    _sub = service.messages.listen(_handleMessage);
  }

  final Ref ref;
  StreamSubscription<String>? _sub;

  void _handleMessage(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final String? cmd = decoded["cmd"];
      if (cmd == null) return;

      if (cmd == "wifi_status") {
        final String st = "${decoded["status"] ?? ""}";
        if (st == "connecting") {
          state = state.copyWith(
            status: WifiConfigStatus.connecting,
            activeSsid: decoded["ssid"]?.toString(),
            clearError: true,
          );
        } else if (st == "connected") {
          state = state.copyWith(
            status: WifiConfigStatus.connected,
            newIp: decoded["ip"]?.toString(),
            activeSsid: decoded["ssid"]?.toString(),
            activeMode: "sta",
            clearError: true,
          );
        } else if (st == "failed") {
          state = state.copyWith(
            status: WifiConfigStatus.failed,
            errorMessage: decoded["error"]?.toString() ?? "Failed to join network",
          );
        } else if (st == "reset") {
          state = state.copyWith(
            status: WifiConfigStatus.reset,
            newIp: "192.168.4.1",
            activeSsid: "CartRobot_Setup",
            activeMode: "ap",
            clearError: true,
          );
        }
      } else if (cmd == "wifi_scan_results") {
        final dynamic list = decoded["networks"];
        if (list is List) {
          final List<WifiNetwork> networks = list
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> e) => WifiNetwork.fromJson(e))
              .where((WifiNetwork n) => n.ssid.trim().isNotEmpty)
              .toList();
          networks.sort((WifiNetwork a, WifiNetwork b) => b.rssi.compareTo(a.rssi));
          state = state.copyWith(
            status: WifiConfigStatus.idle,
            availableNetworks: networks,
            clearError: true,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> scanNetworks() async {
    state = state.copyWith(status: WifiConfigStatus.scanning, clearError: true);
    final WebSocketService service = ref.read(websocketServiceProvider);
    if (service.currentStatus == SocketStatus.connected) {
      service.send(RobotCommands.wifiScan());
      return;
    }

    // Fallback to HTTP scan if WebSocket isn't connected yet
    final String host = ref.read(settingsProvider).ip;
    final int port = ref.read(settingsProvider).port;
    try {
      final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final Uri uri = Uri.parse("http://$host:$port/wifi/scan");
      final HttpClientRequest req = await client.getUrl(uri);
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final String body = await utf8.decoder.bind(res).join();
        final dynamic decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded["networks"] is List) {
          final List<WifiNetwork> networks = (decoded["networks"] as List)
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> e) => WifiNetwork.fromJson(e))
              .where((WifiNetwork n) => n.ssid.trim().isNotEmpty)
              .toList();
          networks.sort((WifiNetwork a, WifiNetwork b) => b.rssi.compareTo(a.rssi));
          state = state.copyWith(status: WifiConfigStatus.idle, availableNetworks: networks);
          return;
        }
      }
      state = state.copyWith(status: WifiConfigStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: WifiConfigStatus.idle,
        errorMessage: "Scan failed: ensure phone is on CartRobot_Setup Wi-Fi",
      );
    }
  }

  Future<void> connectSharedWifi(String ssid, String password) async {
    final String s = ssid.trim();
    if (s.isEmpty) {
      state = state.copyWith(
        status: WifiConfigStatus.failed,
        errorMessage: "Please enter or select a Wi-Fi network name",
      );
      return;
    }

    state = state.copyWith(
      status: WifiConfigStatus.connecting,
      activeSsid: s,
      clearError: true,
      clearNewIp: true,
    );

    final WebSocketService service = ref.read(websocketServiceProvider);
    if (service.currentStatus == SocketStatus.connected) {
      service.send(RobotCommands.wifiConnect(s, password));
      return;
    }

    // Fallback to HTTP connect if WS is not established
    final String host = ref.read(settingsProvider).ip;
    final int port = ref.read(settingsProvider).port;
    try {
      final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final Uri uri = Uri.parse("http://$host:$port/wifi/connect");
      final HttpClientRequest req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, String>{"ssid": s, "password": password}));
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final String body = await utf8.decoder.bind(res).join();
        final dynamic decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded["ok"] == true) {
          state = state.copyWith(
            status: WifiConfigStatus.connected,
            newIp: decoded["ip"]?.toString(),
            activeSsid: s,
            activeMode: "sta",
          );
          return;
        }
      }
      state = state.copyWith(
        status: WifiConfigStatus.failed,
        errorMessage: "Connection timed out. Check password or router distance.",
      );
    } catch (_) {
      // Robot may have switched networks; waiting for verification
    }
  }

  Future<void> resetToHotspot() async {
    state = state.copyWith(status: WifiConfigStatus.connecting, clearError: true);
    final WebSocketService service = ref.read(websocketServiceProvider);
    if (service.currentStatus == SocketStatus.connected) {
      service.send(RobotCommands.wifiReset());
    } else {
      final String host = ref.read(settingsProvider).ip;
      final int port = ref.read(settingsProvider).port;
      try {
        final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final Uri uri = Uri.parse("http://$host:$port/wifi/reset");
        final HttpClientRequest req = await client.postUrl(uri);
        await req.close().timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    state = state.copyWith(
      status: WifiConfigStatus.reset,
      newIp: "192.168.4.1",
      activeSsid: "CartRobot_Setup",
      activeMode: "ap",
    );
  }

  void clearStatus() {
    state = state.copyWith(status: WifiConfigStatus.idle, clearError: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<WifiNotifier, WifiState> wifiProvider =
    StateNotifierProvider<WifiNotifier, WifiState>((Ref ref) => WifiNotifier(ref));
