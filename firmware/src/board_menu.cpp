#include "board_menu.h"

#include <Arduino.h>
#include <esp_system.h>
#include <string.h>

#include "config.h"
#include "webserver.h"

static constexpr uint32_t kMenuEnterHoldMs = 3000;
static constexpr uint32_t kShortPressMaxMs = 700;
static constexpr uint32_t kDebounceMs = 45;

static bool s_inMenu = false;
static uint8_t s_item = 0;

enum class MenuItem : uint8_t { ResetHotspot = 0, RestartEsp, Exit, Count };
static constexpr uint8_t kMenuCount = static_cast<uint8_t>(MenuItem::Count);

static bool s_b2Stable = true;
static bool s_b2LastRaw = true;
static uint32_t s_b2LastChangeMs = 0;
static uint32_t s_b2DownAt = 0;
static bool s_menuEnterArmed = false;
static bool s_ignoreNextB2Release = false;

static bool s_b1Stable = true;
static bool s_b1LastRaw = true;
static uint32_t s_b1LastChangeMs = 0;

static bool s_menuPrevB1 = false;
static bool s_menuPrevB2 = false;

static void debounce(bool rawHigh, bool &lastRaw, uint32_t &lastChangeMs, bool &stable) {
  const uint32_t now = millis();
  if (rawHigh != lastRaw) {
    lastRaw = rawHigh;
    lastChangeMs = now;
  }
  if ((now - lastChangeMs) >= kDebounceMs && rawHigh != stable) {
    stable = rawHigh;
  }
}

void boardMenuInit() {
  s_inMenu = false;
  s_item = 0;
  s_b2Stable = true;
  s_b2LastRaw = true;
  s_b2DownAt = 0;
  s_menuEnterArmed = false;
  s_ignoreNextB2Release = false;
  s_b1Stable = true;
  s_b1LastRaw = true;
}

bool boardMenuIsActive() {
  return s_inMenu;
}

void boardMenuGetLines(char line1[17], char line2[17]) {
  strncpy(line1, "SETUP MENU", 16);
  line1[16] = '\0';
  switch (static_cast<MenuItem>(s_item)) {
    case MenuItem::ResetHotspot:
      strncpy(line2, "1.RESET HOTSPOT", 16);
      break;
    case MenuItem::RestartEsp:
      strncpy(line2, "2.RESTART ESP?", 16);
      break;
    case MenuItem::Exit:
    default:
      strncpy(line2, "3.EXIT MENU", 16);
      break;
  }
  line2[16] = '\0';
}

void boardMenuTick(uint32_t now, void (*onAutoShortPress)()) {
  const bool rawB2High = digitalRead(PIN_BUTTON_AUTO_MODE) == HIGH;
  debounce(rawB2High, s_b2LastRaw, s_b2LastChangeMs, s_b2Stable);
  const bool b2Down = !s_b2Stable;

  const bool rawB1High = digitalRead(PIN_BUTTON_DRIVE_ENABLE) == HIGH;
  debounce(rawB1High, s_b1LastRaw, s_b1LastChangeMs, s_b1Stable);
  const bool b1Down = !s_b1Stable;

  if (s_inMenu) {
    if (b1Down && !s_menuPrevB1) {
      s_item = static_cast<uint8_t>((s_item + 1) % kMenuCount);
    }
    if (b2Down && !s_menuPrevB2) {
      switch (static_cast<MenuItem>(s_item)) {
        case MenuItem::ResetHotspot:
          Serial.println("[MENU] reset hotspot");
          webserverResetToHotspot();
          s_inMenu = false;
          s_menuEnterArmed = false;
          s_ignoreNextB2Release = true;
          break;
        case MenuItem::RestartEsp:
          Serial.println("[MENU] restart");
          delay(100);
          esp_restart();
          break;
        case MenuItem::Exit:
        default:
          s_inMenu = false;
          s_menuEnterArmed = false;
          s_ignoreNextB2Release = true;
          Serial.println("[MENU] exit");
          break;
      }
    }
    s_menuPrevB1 = b1Down;
    s_menuPrevB2 = b2Down;
    return;
  }

  if (b2Down) {
    if (s_b2DownAt == 0) {
      s_b2DownAt = now;
    }
    if (!s_menuEnterArmed && (now - s_b2DownAt) >= kMenuEnterHoldMs) {
      s_inMenu = true;
      s_item = 0;
      s_menuEnterArmed = true;
      s_ignoreNextB2Release = true;
      s_menuPrevB1 = b1Down;
      s_menuPrevB2 = b2Down;
      Serial.println("[MENU] enter (hold BTN2)");
    }
  } else {
    if (s_b2DownAt != 0) {
      const uint32_t dur = now - s_b2DownAt;
      s_b2DownAt = 0;
      if (s_menuEnterArmed) {
        s_menuEnterArmed = false;
        return;
      }
      if (s_ignoreNextB2Release) {
        s_ignoreNextB2Release = false;
        return;
      }
      if (dur <= kShortPressMaxMs && onAutoShortPress != nullptr) {
        onAutoShortPress();
      }
    }
  }
}
