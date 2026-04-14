import "dart:convert";

enum DriveState { fwd, rev, stop }

enum RouteState { idle, recording, playing, playingReverse }

class Telemetry {
  const Telemetry({
    required this.distCm,
    required this.steerPwm,
    required this.drive,
    required this.enabled,
    required this.auto,
    required this.navLeds,
    required this.headlight,
    required this.buzzerMuted,
    required this.btn1,
    required this.btn2,
    required this.sensitivity,
    required this.uptimeS,
    required this.routeState,
    required this.routeStep,
    required this.routeTotal,
  });

  final int distCm;
  final int steerPwm;
  final DriveState drive;
  final bool enabled;
  final bool auto;
  final bool navLeds;
  final bool headlight;
  final bool buzzerMuted;
  final bool btn1;
  final bool btn2;
  final double sensitivity;
  final int uptimeS;
  final RouteState routeState;
  final int routeStep;
  final int routeTotal;

  static const Telemetry initial = Telemetry(
    distCm: 250,
    steerPwm: 0,
    drive: DriveState.stop,
    enabled: false,
    auto: false,
    navLeds: true,
    headlight: false,
    buzzerMuted: false,
    btn1: false,
    btn2: false,
    sensitivity: 1.0,
    uptimeS: 0,
    routeState: RouteState.idle,
    routeStep: 0,
    routeTotal: 0,
  );

  static Telemetry? tryParse(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (!decoded.containsKey("dist_cm")) {
        return null;
      }
      return Telemetry.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    int intVal(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
    double dblVal(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
    bool boolVal(dynamic v, bool fallback) => v is bool ? v : fallback;

    final String driveRaw = "${json["drive"] ?? "stop"}";
    final String routeRaw = "${json["route_state"] ?? "idle"}";

    return Telemetry(
      distCm: intVal(json["dist_cm"], 250).clamp(0, 9999),
      steerPwm: intVal(json["steer_pwm"], 0).clamp(0, 255),
      drive: switch (driveRaw) {
        "fwd" => DriveState.fwd,
        "rev" => DriveState.rev,
        _ => DriveState.stop,
      },
      enabled: boolVal(json["enabled"], false),
      auto: boolVal(json["auto"], false),
      navLeds: boolVal(json["nav_leds"], true),
      headlight: boolVal(json["headlight"], false),
      buzzerMuted: boolVal(json["buzzer_muted"], false),
      btn1: boolVal(json["btn1"], false),
      btn2: boolVal(json["btn2"], false),
      sensitivity: dblVal(json["sensitivity"], 1.0).clamp(0.1, 2.0),
      uptimeS: intVal(json["uptime_s"], 0).clamp(0, 0x7FFFFFFF),
      routeState: switch (routeRaw) {
        "recording" => RouteState.recording,
        "playing" => RouteState.playing,
        "playing_reverse" => RouteState.playingReverse,
        _ => RouteState.idle,
      },
      routeStep: intVal(json["route_step"], 0).clamp(0, 500),
      routeTotal: intVal(json["route_total"], 0).clamp(0, 500),
    );
  }
}
