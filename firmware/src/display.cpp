// firmware/src/display.cpp
#include "display.h"
#include "webserver.h"

#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <stdio.h>
#include <string.h>

static LiquidCrystal_I2C *s_lcd = nullptr;
static uint8_t s_lcdAddr = LCD_I2C_ADDR_PRIMARY;
static uint32_t s_lastDrawMs = 0;
static char s_line1[17];
static char s_line2[17];
static bool s_dirty = false;

static bool i2cDeviceResponds(uint8_t addr7) {
  Wire.beginTransmission(addr7);
  return Wire.endTransmission() == 0;
}

static void logFullI2cScan() {
  Serial.printf("[LCD] I2C scan SDA=%d SCL=%d:\n", PIN_I2C_SDA, PIN_I2C_SCL);
  int found = 0;
  for (uint8_t a = 0x03; a <= 0x77; ++a) {
    if (i2cDeviceResponds(a)) {
      Serial.printf("  device 0x%02X\n", static_cast<unsigned>(a));
      ++found;
    }
  }
  if (found == 0) {
    Serial.println("  (none — check wiring, level, pins in config.h)");
  }
}

static uint8_t scanLcdI2cAddress() {
  if (LCD_I2C_ADDR_FORCE != 0) {
    Serial.printf("[LCD] forced I2C addr 0x%02X\n", static_cast<unsigned>(LCD_I2C_ADDR_FORCE));
    return LCD_I2C_ADDR_FORCE;
  }

  static const uint8_t kPcf8574Order[] = {
      LCD_I2C_ADDR_PRIMARY,
      LCD_I2C_ADDR_FALLBACK,
      0x38,
      0x20,
      0x21,
      0x22,
      0x23,
      0x24,
      0x25,
      0x26,
      0x39,
      0x3A,
      0x3B,
      0x3C,
      0x3D,
      0x3E,
  };
  for (uint8_t addr : kPcf8574Order) {
    if (i2cDeviceResponds(addr)) {
      return addr;
    }
  }
  for (uint8_t addr = 0x20; addr <= 0x3F; ++addr) {
    if (i2cDeviceResponds(addr)) {
      return addr;
    }
  }
  Serial.println("[LCD] no I2C backpack found; defaulting 0x27 (likely wrong)");
  return LCD_I2C_ADDR_PRIMARY;
}

static void requestDraw(const char *l1, const char *l2) {
  char next1[17];
  char next2[17];
  strncpy(next1, l1, 16);
  next1[16] = '\0';
  strncpy(next2, l2, 16);
  next2[16] = '\0';
  if (strncmp(next1, s_line1, 17) == 0 && strncmp(next2, s_line2, 17) == 0) {
    return;
  }
  strncpy(s_line1, next1, 17);
  strncpy(s_line2, next2, 17);
  s_dirty = true;
}

static void requestDrawWifiSummary() {
  // Pull freshest active interface IP so LCD matches runtime network mode.
  webserverRefreshRobotIp();
  const IPAddress ip = webserverRobotIp();
  char l1[17];
  char l2[17];
  const bool haveIp = !(ip[0] == 0 && ip[1] == 0 && ip[2] == 0 && ip[3] == 0);
  if (!haveIp) {
    requestDraw("AP starting...", "please wait");
    return;
  }
  snprintf(l1, sizeof(l1), "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
  if (webserverWifiUsingSta()) {
    snprintf(l2, sizeof(l2), "STA %.12s", webserverActiveSsid());
  } else {
    snprintf(l2, sizeof(l2), "AP  %.12s", WIFI_AP_SSID);
  }
  requestDraw(l1, l2);
}


void displayInit() {
#if defined(ESP32)
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, LCD_I2C_HZ);
#else
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(LCD_I2C_HZ);
#endif
  delay(50);

  logFullI2cScan();
  const uint8_t addr = scanLcdI2cAddress();
  s_lcdAddr = addr;
  Serial.printf("[LCD] using backpack addr 0x%02X (set LCD_I2C_ADDR_FORCE if wrong)\n",
                static_cast<unsigned>(addr));

  if (s_lcd != nullptr) {
    delete s_lcd;
    s_lcd = nullptr;
  }
  s_lcd = new LiquidCrystal_I2C(addr, 16, 2);
  // Library init() calls Wire.begin() with no args; restore our pins + speed after.
  s_lcd->init();
#if defined(ESP32)
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, LCD_I2C_HZ);
#else
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(LCD_I2C_HZ);
#endif
  s_lcd->backlight();
  s_lastDrawMs = 0;

  s_lcd->clear();
  s_lcd->setCursor(0, 0);
  s_lcd->print("LCD init OK");
  s_lcd->setCursor(0, 1);
  s_lcd->print("addr 0x");
  if (addr < 16) {
    s_lcd->print('0');
  }
  s_lcd->print(addr, HEX);
  delay(300);
}

void displayShowWifiReady() {
  requestDrawWifiSummary();
}

void displayShowMenu(const char *line1, const char *line2) {
  requestDraw(line1, line2);
}

void displayForceReinit() {
  // Wire.end() tears down the I2C hardware peripheral completely.
  // Wire.begin() alone is insufficient — it only reconfigures, leaving
  // corrupted hardware state from the WiFi radio intact.
  if (s_lcd == nullptr) {
    return;
  }
  Wire.end();  // full hardware teardown
  delay(80);
#if defined(ESP32)
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, LCD_I2C_HZ);
#else
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(LCD_I2C_HZ);
#endif
  delay(50);
  // Re-scan in case the backpack address changed / was misdetected after RF startup.
  const uint8_t addr = scanLcdI2cAddress();
  s_lcdAddr = addr;
  if (s_lcd != nullptr) {
    delete s_lcd;
    s_lcd = nullptr;
  }
  s_lcd = new LiquidCrystal_I2C(addr, 16, 2);
  s_lcd->init();  // full controller init on a fresh object
  // s_lcd->init() calls Wire.begin() with no args; restore our pins.
#if defined(ESP32)
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, LCD_I2C_HZ);
#else
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(LCD_I2C_HZ);
#endif
  delay(30);
  s_lcd->backlight();
  delay(30);
  Serial.printf("[LCD] reinit addr=0x%02X\n", static_cast<unsigned>(s_lcdAddr));
}

// Call this only from setup() context (NOT from RTOS tasks).
void displayShowConnecting(const char *ssid, uint32_t elapsedMs, uint32_t timeoutMs) {
  if (s_lcd == nullptr) {
    return;
  }
  (void)timeoutMs;
  char l1[17];
  char l2[17];
  const uint32_t elapsed_s = elapsedMs / 1000U;
  const int dots = static_cast<int>((elapsedMs / 400U) % 4);
  const char *dotStr = dots == 0 ? "" : dots == 1 ? "." : dots == 2 ? ".." : "...";
  snprintf(l1, sizeof(l1), "WiFi search%s", dotStr);
  snprintf(l2, sizeof(l2), "%-10.10s %2lus", ssid != nullptr ? ssid : "?",
           (unsigned long)elapsed_s);
  requestDraw(l1, l2);
}


void displayRedrawHardware() {
  if (s_lcd == nullptr) {
    return;
  }
  s_lcd->clear();
  s_lcd->setCursor(0, 0);
  s_lcd->print(s_line1);
  s_lcd->setCursor(0, 1);
  s_lcd->print(s_line2);
  s_lastDrawMs = millis();
  s_dirty = false;
}

void displayAfterNetworkUp() {
  displayShowWifiReady();
  displayRedrawHardware();
  s_lastDrawMs = millis();
  s_dirty = false;
  Serial.printf("[LCD] shown: \"%s\" / \"%s\" (addr=0x%02X)\n", s_line1, s_line2,
                static_cast<unsigned>(s_lcdAddr));
}

void displayShowWaiting() {
  requestDraw("Waiting...", "No connection");
}

static const char *driveTag(DriveCmd d) {
  switch (d) {
    case DriveCmd::Forward:
      return "FWD";
    case DriveCmd::Reverse:
      return "REV";
    case DriveCmd::Stop:
    default:
      return "STP";
  }
}

static char s_wifiNotice1[17] = "";
static char s_wifiNotice2[17] = "";
static uint32_t s_wifiNoticeUntilMs = 0;

void displayShowWifiConnecting(const char *ssid) {
  snprintf(s_wifiNotice1, sizeof(s_wifiNotice1), "CONNECTING WIFI");
  snprintf(s_wifiNotice2, sizeof(s_wifiNotice2), "%.16s", ssid ? ssid : "");
  s_wifiNoticeUntilMs = millis() + 15000;
  requestDraw(s_wifiNotice1, s_wifiNotice2);
  displayRedrawHardware();
}

void displayShowWifiConnected(const char *ip, const char *ssid) {
  (void)ssid;
  snprintf(s_wifiNotice1, sizeof(s_wifiNotice1), "NEW IP (WIFI):");
  snprintf(s_wifiNotice2, sizeof(s_wifiNotice2), "%.16s", ip ? ip : "");
  s_wifiNoticeUntilMs = millis() + 10000;
  requestDraw(s_wifiNotice1, s_wifiNotice2);
  displayRedrawHardware();
}

void displayShowWifiResetHotspot() {
  snprintf(s_wifiNotice1, sizeof(s_wifiNotice1), "HOTSPOT RESET");
  snprintf(s_wifiNotice2, sizeof(s_wifiNotice2), "IP 192.168.4.1");
  s_wifiNoticeUntilMs = millis() + 6000;
  requestDraw(s_wifiNotice1, s_wifiNotice2);
  displayRedrawHardware();
}

void displayShowNormal(uint8_t steerPwm, DriveCmd drive, float distCm, float sensitivity,
                       bool wsConnected, bool motorEnabled, bool autoMode) {
  (void)steerPwm;
  (void)sensitivity;
  const uint32_t now = millis();
  if (s_wifiNoticeUntilMs != 0 && static_cast<int32_t>(s_wifiNoticeUntilMs - now) > 0) {
    requestDraw(s_wifiNotice1, s_wifiNotice2);
    return;
  }
  s_wifiNoticeUntilMs = 0;

  char l1[17];
  char l2[17];
  const bool b1Down = digitalRead(PIN_BUTTON_DRIVE_ENABLE) == LOW;
  const bool b2Down = digitalRead(PIN_BUTTON_AUTO_MODE) == LOW;

  webserverRefreshRobotIp();
  const IPAddress ip = webserverRobotIp();
  const bool usingSta = webserverWifiUsingSta();
  const bool haveIp = !(ip[0] == 0 && ip[1] == 0 && ip[2] == 0 && ip[3] == 0);

  if (!wsConnected) {
    if (haveIp && usingSta) {
      snprintf(l1, sizeof(l1), "STA %u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
    } else if (haveIp) {
      snprintf(l1, sizeof(l1), "AP %u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
    } else {
      snprintf(l1, sizeof(l1), "No link");
    }
    snprintf(l2, sizeof(l2), "1:%s 2:%s", b1Down ? "DN" : "UP", b2Down ? "DN" : "UP");
    requestDraw(l1, l2);
    return;
  }

  snprintf(l1, sizeof(l1), "E:%s A:%s %s", motorEnabled ? "ON" : "OFF", autoMode ? "ON" : "OFF",
           driveTag(drive));
  if (distCm >= 0.0f && distCm < 400.0f) {
    snprintf(l2, sizeof(l2), "1:%s 2:%s %3.0f", b1Down ? "DN" : "UP", b2Down ? "DN" : "UP",
             static_cast<double>(distCm));
  } else {
    snprintf(l2, sizeof(l2), "1:%s 2:%s", b1Down ? "DN" : "UP", b2Down ? "DN" : "UP");
  }
  requestDraw(l1, l2);
}

static const char *autoSubLabel(AutoFsm s) {
  switch (s) {
    case AutoFsm::AvoidTurn:
    case AutoFsm::AvoidForward:
    case AutoFsm::Resume:
      return "AVOID";
    case AutoFsm::Forward:
    default:
      return "FWD";
  }
}

void displayShowAuto(float distCm, AutoFsm autoState) {
  char l1[17];
  char l2[17];
  if (distCm >= 0.0f && distCm < 400.0f) {
    snprintf(l1, sizeof(l1), "AUTO Dst:%02.0fcm", static_cast<double>(distCm));
  } else {
    snprintf(l1, sizeof(l1), "AUTO Dst:--cm");
  }
  snprintf(l2, sizeof(l2), "%s", autoSubLabel(autoState));
  requestDraw(l1, l2);
}

void displayShowRecording(uint16_t steps) {
  char l2[17];
  snprintf(l2, sizeof(l2), "Steps: %03u", static_cast<unsigned>(steps));
  requestDraw("RECORDING...", l2);
}

void displayShowPlayback(uint16_t idx, uint16_t total, float distCm, bool reverse) {
  char l1[17];
  char l2[17];
  if (reverse) {
    snprintf(l1, sizeof(l1), "RETURN %u/%u", static_cast<unsigned>(idx),
             static_cast<unsigned>(total));
  } else {
    snprintf(l1, sizeof(l1), "PLAYBACK %u/%u", static_cast<unsigned>(idx),
             static_cast<unsigned>(total));
  }
  if (distCm >= 0.0f && distCm < 400.0f) {
    snprintf(l2, sizeof(l2), "Dst:%02.0fcm", static_cast<double>(distCm));
  } else {
    snprintf(l2, sizeof(l2), "Dst:--cm");
  }
  requestDraw(l1, l2);
}

void displayUpdate() {
  if (s_lcd == nullptr) {
    return;
  }
  const uint32_t now = millis();
  if (!s_dirty) {
    return;
  }
  const bool throttle =
      (s_lastDrawMs != 0) && (now - s_lastDrawMs < LCD_UPDATE_MIN_INTERVAL_MS);
  if (throttle) {
    return;
  }
  displayRedrawHardware();
}
