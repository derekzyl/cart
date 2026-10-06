// firmware/src/webserver.cpp
#include "webserver.h"
#include "config.h"
#include "route.h"

#include <ArduinoJson.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ESPmDNS.h>
#include <WiFi.h>
#include <esp_wifi.h>

#include <cstring>

static AsyncWebServer s_server(WEBSOCKET_PORT);
static AsyncWebSocket s_wsRoot("/");
static AsyncWebSocket s_wsPath("/ws");

static bool s_wifiUsingSta = false;
static IPAddress s_robotIp;

static void wsTextAll(const char *payload) {
  s_wsRoot.textAll(payload);
  s_wsPath.textAll(payload);
}

bool webserverWifiUsingSta() {
  return s_wifiUsingSta;
}

IPAddress webserverRobotIp() {
  return s_robotIp;
}

void webserverRefreshRobotIp() {
  if (s_wifiUsingSta) {
    if (WiFi.status() == WL_CONNECTED) {
      const IPAddress ip = WiFi.localIP();
      if (ip != IPAddress(0u, 0u, 0u, 0u)) {
        s_robotIp = ip;
      }
    }
  } else {
    const IPAddress ap = WiFi.softAPIP();
    if (ap != IPAddress(0u, 0u, 0u, 0u)) {
      s_robotIp = ap;
    }
  }
}

static void handleWsMessage(AsyncWebSocketClient *client, const char *payload, size_t len) {
  if (len == 0 || payload == nullptr) {
    Serial.println("[WSDBG] empty payload");
    return;
  }
  Serial.printf("[WSDBG] rx %u bytes from client %u: %.80s\n",
                static_cast<unsigned>(len),
                static_cast<unsigned>(client ? client->id() : 0U), payload);

  JsonDocument doc;
  const DeserializationError err = deserializeJson(doc, payload, len);
  if (err) {
    Serial.printf("[WSDBG] json parse failed: %s\n", err.c_str());
    return;
  }

  const char *cmd = doc["cmd"];
  if (cmd == nullptr) {
    Serial.println("[WSDBG] missing cmd");
    return;
  }
  Serial.printf("[WSDBG] cmd=%s\n", cmd);

  if (strcmp(cmd, "ping") == 0) {
    if (takeStateMutex()) {
      g_state.lastWsMessageMs = millis();
      g_state.watchdogTripped = false;
      giveStateMutex();
    }
    JsonDocument reply;
    reply["cmd"] = "pong";
    char buf[96];
    const size_t n = serializeJson(reply, buf, sizeof(buf));
    if (n > 0 && n < sizeof(buf)) {
      wsTextAll(buf);
      Serial.println("[WSDBG] pong broadcast");
    }
    return;
  }

  if (!takeStateMutex()) {
    return;
  }

  g_state.lastWsMessageMs = millis();
  g_state.watchdogTripped = false;

  if (strcmp(cmd, "enable") == 0) {
    g_state.motorEnabled = doc["state"] | false;
    Serial.printf("[WSDBG] enable=%u\n", g_state.motorEnabled ? 1U : 0U);
    giveStateMutex();
    return;
  }

  if (strcmp(cmd, "auto") == 0) {
    const bool st = doc["state"] | false;
    g_state.autoMode = st;
    if (st) {
      g_state.pendingRoute = PendingRouteAction::Stop;
    }
    Serial.printf("[WSDBG] auto=%u\n", st ? 1U : 0U);
    giveStateMutex();
    return;
  }

  if (strcmp(cmd, "leds") == 0) {
    if (doc["nav"].is<bool>()) {
      g_state.navLedsEnabled = doc["nav"].as<bool>();
    }
    if (doc["headlight"].is<bool>()) {
      g_state.headlightOn = doc["headlight"].as<bool>();
    }
    Serial.printf("[WSDBG] leds nav=%u head=%u\n", g_state.navLedsEnabled ? 1U : 0U,
                  g_state.headlightOn ? 1U : 0U);
    giveStateMutex();
    return;
  }

  if (strcmp(cmd, "buzzer") == 0) {
    if (doc["mute"].is<bool>()) {
      g_state.buzzerMuted = doc["mute"].as<bool>();
    }
    Serial.printf("[WSDBG] buzzer mute=%u\n", g_state.buzzerMuted ? 1U : 0U);
    giveStateMutex();
    return;
  }

  if (strcmp(cmd, "route") == 0) {
    const char *action = doc["action"];
    if (action != nullptr) {
      if (strcmp(action, "record_start") == 0) {
        g_state.autoMode = false;
        g_state.pendingRoute = PendingRouteAction::RecordStart;
      } else if (strcmp(action, "record_stop") == 0) {
        g_state.pendingRoute = PendingRouteAction::RecordStop;
      } else if (strcmp(action, "playback") == 0) {
        g_state.autoMode = false;
        g_state.pendingRoute = PendingRouteAction::Playback;
      } else if (strcmp(action, "playback_reverse") == 0) {
        g_state.autoMode = false;
        g_state.pendingRoute = PendingRouteAction::PlaybackReverse;
      } else if (strcmp(action, "stop") == 0) {
        g_state.pendingRoute = PendingRouteAction::Stop;
      } else if (strcmp(action, "clear") == 0) {
        g_state.pendingRoute = PendingRouteAction::ClearMemory;
      }
    }
    giveStateMutex();
    Serial.println("[WSDBG] route command applied");
    return;
  }

  if (g_state.autoMode && (strcmp(cmd, "move") == 0 || strcmp(cmd, "steer") == 0)) {
    giveStateMutex();
    return;
  }

  if (routeGetState() == RouteFsm::Playing || routeGetState() == RouteFsm::PlayingReverse) {
    if (strcmp(cmd, "move") == 0 || strcmp(cmd, "steer") == 0) {
      giveStateMutex();
      return;
    }
  }

  if (strcmp(cmd, "move") == 0) {
    const char *dir = doc["dir"];
    if (dir == nullptr) {
      giveStateMutex();
      return;
    }
    DriveCmd next = DriveCmd::Stop;
    if (strcmp(dir, "fwd") == 0) {
      next = DriveCmd::Forward;
      if (g_state.lastCommandedSpeedPwm < DEFAULT_COMMANDED_SPEED_PWM) {
        g_state.lastCommandedSpeedPwm = DEFAULT_COMMANDED_SPEED_PWM;
      }
    } else if (strcmp(dir, "rev") == 0) {
      next = DriveCmd::Reverse;
    } else if (strcmp(dir, "stop") == 0) {
      next = DriveCmd::Stop;
    }
    g_state.driveCmd = next;
    Serial.printf("[WSDBG] move=%u\n", static_cast<unsigned>(next));
    giveStateMutex();
    return;
  }

  if (strcmp(cmd, "steer") == 0) {
    const char *dir = doc["dir"];
    const int pwmIn = doc["pwm"] | 0;
    const uint8_t pwm = static_cast<uint8_t>(constrain(pwmIn, 0, 255));
    if (pwm > 0) {
      g_state.lastCommandedSpeedPwm = pwm;
    }
    SteerCmd s = SteerCmd::Center;
    if (dir != nullptr) {
      if (strcmp(dir, "left") == 0) {
        s = SteerCmd::Left;
      } else if (strcmp(dir, "right") == 0) {
        s = SteerCmd::Right;
      } else if (strcmp(dir, "center") == 0) {
        s = SteerCmd::Center;
      }
    }
    g_state.steerCmd = s;
    g_state.steerPwmRaw = pwm;
    Serial.printf("[WSDBG] steer=%u pwm=%u\n", static_cast<unsigned>(s),
                  static_cast<unsigned>(pwm));
    giveStateMutex();
    return;
  }

  Serial.printf("[WSDBG] unhandled cmd=%s\n", cmd);
  giveStateMutex();
}

static void onWsEvent(AsyncWebSocket *server, AsyncWebSocketClient *client, AwsEventType type,
                      void *arg, uint8_t *data, size_t len) {
  (void)server;
  (void)arg;

  switch (type) {
    case WS_EVT_CONNECT: {
      int n = 0;
      if (takeStateMutex()) {
        g_state.wsClientCount += 1;
        g_state.lastWsMessageMs = millis();
        g_state.watchdogTripped = false;
        n = g_state.wsClientCount;
        giveStateMutex();
      }
      IPAddress rip = client ? client->remoteIP() : IPAddress();
      Serial.printf("[WS] client connected id=%u from %u.%u.%u.%u (%d total)\n",
                    static_cast<unsigned>(client ? client->id() : 0U),
                    rip[0], rip[1], rip[2], rip[3], n);
      break;
    }
    case WS_EVT_DISCONNECT: {
      int n = 0;
      if (takeStateMutex()) {
        g_state.wsClientCount -= 1;
        if (g_state.wsClientCount < 0) {
          g_state.wsClientCount = 0;
        }
        n = g_state.wsClientCount;
        giveStateMutex();
      }
      Serial.printf("[WS] client disconnected id=%u (%d total)\n",
                    static_cast<unsigned>(client ? client->id() : 0U), n);
      (void)n;
      break;
    }
    case WS_EVT_DATA: {
      AwsFrameInfo *info = static_cast<AwsFrameInfo *>(arg);
      if (info->opcode == WS_TEXT && info->final && info->index == 0) {
        if (len < 512) {
          char buf[512];
          memcpy(buf, data, len);
          buf[len] = '\0';
          handleWsMessage(client, buf, len);
        }
      } else {
        Serial.printf("[WSDBG] frame ignored op=%u final=%u idx=%u len=%u\n",
                      static_cast<unsigned>(info->opcode),
                      static_cast<unsigned>(info->final),
                      static_cast<unsigned>(info->index),
                      static_cast<unsigned>(len));
      }
      break;
    }
    default:
      break;
  }
}

void webserverInit() {
  s_wifiUsingSta = false;
  s_robotIp = IPAddress(0u, 0u, 0u, 0u);

  // ── WiFi mode selection ─────────────────────────────────────────────────────
  WiFi.mode(WIFI_FORCE_STA_MODE ? WIFI_STA : WIFI_AP_STA);
  WiFi.setHostname("cart-robot");
  delay(100);

  bool apOk = false;
  if (!WIFI_FORCE_STA_MODE) {
    const IPAddress apLocalIp(WIFI_AP_IP_A, WIFI_AP_IP_B, WIFI_AP_IP_C, WIFI_AP_IP_D);
    const IPAddress apGateway(WIFI_AP_IP_A, WIFI_AP_IP_B, WIFI_AP_IP_C, WIFI_AP_IP_D);
    const IPAddress apSubnet(WIFI_AP_MASK_A, WIFI_AP_MASK_B, WIFI_AP_MASK_C, WIFI_AP_MASK_D);
    WiFi.softAPConfig(apLocalIp, apGateway, apSubnet);
    apOk = WiFi.softAP(WIFI_AP_SSID, WIFI_AP_PASSWORD, 1, 0, 4);
    delay(200);  // let AP DHCP server fully settle before anything else

    if (apOk) {
      s_robotIp = WiFi.softAPIP();
      WiFi.setSleep(false);
      esp_wifi_set_ps(WIFI_PS_NONE);
      Serial.printf("[WiFi] SoftAP \"%s\" IP %s  port %u\n", WIFI_AP_SSID,
                    s_robotIp.toString().c_str(), static_cast<unsigned>(WEBSOCKET_PORT));
    } else {
      Serial.println("[WiFi] softAP FAILED — check SSID/password length");
    }
  } else {
    Serial.println("[WiFi] STA-only mode enabled (SoftAP disabled)");
  }

  // Start the WebSocket server NOW — as soon as the AP is up.
  // If phone connects to the hotspot during the STA search, it can already
  // reach the robot at 192.168.4.1:8080 without waiting 12+ seconds.
  s_server.on("/health", HTTP_GET, [](AsyncWebServerRequest *request) {
    webserverRefreshRobotIp();
    IPAddress rip = request ? request->client()->remoteIP() : IPAddress();
    Serial.printf("[HTTP] /health from %u.%u.%u.%u\n", rip[0], rip[1], rip[2], rip[3]);
    JsonDocument doc;
    doc["ok"] = true;
    doc["ws_port"] = WEBSOCKET_PORT;
    doc["ws_paths"] = "/,/ws";
    doc["wifi_mode"] = s_wifiUsingSta ? "sta" : "ap";
    doc["ip"] = s_robotIp.toString();
    doc["ap_ssid"] = WIFI_AP_SSID;
    if (s_wifiUsingSta) {
      doc["sta_ssid"] = WIFI_STA_SSID;
    }
    char out[256];
    const size_t n = serializeJson(doc, out, sizeof(out));
    request->send(200, "application/json", n > 0 ? out : "{\"ok\":true}");
  });

  s_wsRoot.onEvent(onWsEvent);
  s_wsPath.onEvent(onWsEvent);
  s_server.addHandler(&s_wsRoot);
  s_server.addHandler(&s_wsPath);
  s_server.begin();
  Serial.printf("[WS] server ready ws://<ip>:%u/ and /ws\n",
                static_cast<unsigned>(WEBSOCKET_PORT));

  // ── Join home router (STA) ─────────────────────────────────────────────────
  const bool wantSta =
      (WIFI_STA_SSID != nullptr && WIFI_STA_SSID[0] != '\0');

  if (wantSta) {
    WiFi.begin(WIFI_STA_SSID,
               (WIFI_STA_PASSWORD != nullptr && WIFI_STA_PASSWORD[0] != '\0')
                   ? WIFI_STA_PASSWORD : nullptr);

    const uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - t0) < WIFI_STA_CONNECT_TIMEOUT_MS) {
      delay(50);
    }

    if (WiFi.status() == WL_CONNECTED) {
      WiFi.setSleep(false);
      esp_wifi_set_ps(WIFI_PS_NONE);
      s_wifiUsingSta = true;
      s_robotIp = WiFi.localIP();
      Serial.printf("[WiFi] STA \"%s\" IP %s\n", WIFI_STA_SSID,
                    WiFi.localIP().toString().c_str());
      if (MDNS.begin("cart-robot")) {
        MDNS.addService("ws", "tcp", WEBSOCKET_PORT);
        Serial.printf("[mDNS] cart-robot.local:%u\n",
                      static_cast<unsigned>(WEBSOCKET_PORT));
      }
    } else {
      Serial.printf("[WiFi] STA timeout\n");
      WiFi.disconnect(true, false);
    }
  }

  if (takeStateMutex()) {
    g_state.wifiReady = s_wifiUsingSta || apOk;
    giveStateMutex();
  }
}


static const char *routeStateJson(RouteFsm s) {
  switch (s) {
    case RouteFsm::Recording:
      return "recording";
    case RouteFsm::Playing:
      return "playing";
    case RouteFsm::PlayingReverse:
      return "playing_reverse";
    case RouteFsm::Idle:
    default:
      return "idle";
  }
}

void webserverBroadcastTelemetry() {
  const uint32_t now = millis();
  static bool s_watchdogAsserted = false;

  if (!takeStateMutex()) {
    return;
  }

  const bool watchdogTripped =
      (g_state.wsClientCount > 0 &&
       (now - g_state.lastWsMessageMs) > WATCHDOG_NO_MESSAGE_MS);

  if (watchdogTripped) {
    if (!s_watchdogAsserted) {
      Serial.println("[WS] watchdog: forcing safe stop");
      s_watchdogAsserted = true;
    }
    g_state.motorEnabled = false;
    g_state.driveCmd = DriveCmd::Stop;
    g_state.watchdogTripped = true;
  } else {
    s_watchdogAsserted = false;
  }

  JsonDocument doc;
  doc["dist_cm"] = g_state.telemetryDistCm;
  doc["steer_pwm"] = g_state.telemetrySteerPwm;

  const char *drv = "stop";
  switch (g_state.telemetryDrive) {
    case DriveCmd::Forward:
      drv = "fwd";
      break;
    case DriveCmd::Reverse:
      drv = "rev";
      break;
    case DriveCmd::Stop:
    default:
      drv = "stop";
      break;
  }
  doc["drive"] = drv;
  doc["enabled"] = g_state.telemetryEnabled;
  doc["auto"] = g_state.telemetryAuto;
  doc["nav_leds"] = g_state.telemetryNavLeds;
  doc["headlight"] = g_state.telemetryHeadlight;
  doc["buzzer_muted"] = g_state.telemetryBuzzerMuted;
  doc["btn1"] = g_state.telemetryBtn1;
  doc["btn2"] = g_state.telemetryBtn2;
  doc["sensitivity"] = g_state.telemetrySensitivity;
  doc["uptime_s"] = now / 1000U;
  doc["route_state"] = routeStateJson(g_state.telemetryRouteState);
  doc["route_step"] = g_state.telemetryRouteStep;
  doc["route_total"] = g_state.telemetryRouteTotal;

  char out[512];
  const size_t n = serializeJson(doc, out, sizeof(out));
  giveStateMutex();

  if (n > 0 && n < sizeof(out)) {
    wsTextAll(out);
  }
}
