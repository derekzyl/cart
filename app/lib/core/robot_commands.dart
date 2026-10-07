class RobotCommands {
  const RobotCommands._();

  static Map<String, dynamic> move(String dir) => <String, dynamic>{"cmd": "move", "dir": dir};
  static Map<String, dynamic> steerAngle(double degrees) =>
      <String, dynamic>{"cmd": "steer_angle", "angle": degrees};
  static Map<String, dynamic> straight() => <String, dynamic>{"cmd": "straight"};
  static Map<String, dynamic> recentre() => <String, dynamic>{"cmd": "recentre"};
  static Map<String, dynamic> getCalib() => <String, dynamic>{"cmd": "get_calib"};
  static Map<String, dynamic> setCalib(Map<String, dynamic> fields) =>
      <String, dynamic>{"cmd": "set_calib", ...fields};
  static Map<String, dynamic> calibJog(String dir, int durationMs) =>
      <String, dynamic>{"cmd": "calib_jog", "dir": dir, "duration_ms": durationMs};
  static Map<String, dynamic> calibMeasureStart(String dir) =>
      <String, dynamic>{"cmd": "calib_measure_start", "dir": dir};
  static Map<String, dynamic> calibMeasureStop(double spanDeg) =>
      <String, dynamic>{"cmd": "calib_measure_stop", "span_deg": spanDeg};
  static Map<String, dynamic> calibSetCentre() => <String, dynamic>{"cmd": "calib_set_centre"};
  static Map<String, dynamic> calibSave() => <String, dynamic>{"cmd": "calib_save"};
  static Map<String, dynamic> calibReset() => <String, dynamic>{"cmd": "calib_reset_defaults"};
  static Map<String, dynamic> enable(bool state) =>
      <String, dynamic>{"cmd": "enable", "state": state};
  static Map<String, dynamic> auto(bool state) => <String, dynamic>{"cmd": "auto", "state": state};
  static Map<String, dynamic> ledsNav(bool nav) => <String, dynamic>{"cmd": "leds", "nav": nav};
  static Map<String, dynamic> headlight(bool state) =>
      <String, dynamic>{"cmd": "leds", "headlight": state};
  static Map<String, dynamic> buzzerMute(bool state) =>
      <String, dynamic>{"cmd": "buzzer", "mute": state};
  static Map<String, dynamic> route(String action, {String name = ""}) =>
      <String, dynamic>{"cmd": "route", "action": action, "name": name};
  static Map<String, dynamic> ping() => <String, dynamic>{"cmd": "ping"};
  static Map<String, dynamic> wifiConnect(String ssid, String password) =>
      <String, dynamic>{"cmd": "wifi_connect", "ssid": ssid, "password": password};
  static Map<String, dynamic> wifiScan() => <String, dynamic>{"cmd": "wifi_scan"};
  static Map<String, dynamic> wifiReset() => <String, dynamic>{"cmd": "wifi_reset"};
}
