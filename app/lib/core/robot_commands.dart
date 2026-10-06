class RobotCommands {
  const RobotCommands._();

  static Map<String, dynamic> move(String dir) => <String, dynamic>{"cmd": "move", "dir": dir};
  static Map<String, dynamic> steer(String dir, int pwm) =>
      <String, dynamic>{"cmd": "steer", "dir": dir, "pwm": pwm.clamp(0, 255)};
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
