#include "board_menu.h"

#include <Arduino.h>
#include <esp_system.h>
#include <string.h>

#include "config.h"
#include "webserver.h"

static constexpr uint32_t kMenuEnterHoldMs = 3000;
static constexpr uint32_t kShortPressMaxMs = 2500;
static constexpr uint32_t kDebounceMs = 45;

static bool s_inMenu = false;
static uint8_t s_item = 0;

enum class MenuItem : uint8_t { ResetHotspot = 0, RestartEsp, Exit, Count };
static constexpr uint8_t kMenuCount = static_cast<uint8_t>(MenuItem::Count);

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

static bool s_b2Armed = false;
static uint32_t s_b2HighSince = 0;
static bool s_b2IsDown = false;

void boardMenuInit() {
  s_inMenu = false;
  s_item = 0;
  s_b2DownAt = 0;
  s_menuEnterArmed = false;
  s_ignoreNextB2Release = false;
  s_b1Stable = true;
  s_b1LastRaw = true;
  s_b2Armed = false;
  s_b2HighSince = 0;
  s_b2IsDown = false;
}

bool boardMenuIsActive() {
  return s_inMenu;
}

void boardMenuOpen() {
  if (s_inMenu) {
    return;
  }
  s_inMenu = true;
  s_item = 0;
  s_menuEnterArmed = false;
  s_ignoreNextB2Release = true;
  s_menuPrevB1 = true;
  s_menuPrevB2 = false;
  Serial.println("[MENU] enter (BTN1)");
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
  // GPIO35 has no internal pull-up. A floating pin reads low and used to
  // look like a held button, which turned auto mode on and blocked the app.
  // Arm the button only after the pin has sat HIGH for 400ms.
  const bool rawB2High = digitalRead(PIN_BUTTON_AUTO_MODE) == HIGH;
  if (rawB2High) {
    if (s_b2HighSince == 0) {
      s_b2HighSince = now;
    }
    if (!s_b2Armed && (now - s_b2HighSince) >= 400) {
      s_b2Armed = true;
      Serial.println("[BTN] BTN2 armed (idle HIGH)");
    }
  } else {
    s_b2HighSince = 0;
  }

  const bool rawB1High = !buttonDriveIsPressed();
  debounce(rawB1High, s_b1LastRaw, s_b1LastChangeMs, s_b1Stable);
  const bool b1Down = !s_b1Stable;

  bool b2Down = false;
  if (s_b2Armed) {
    if (!rawB2High) {
      if (!s_b2IsDown) {
        s_b2IsDown = true;
        s_b2DownAt = now;
        Serial.println("[BTN] BTN2 pressed");
      }
      b2Down = true;
    } else if (s_b2IsDown) {
      const uint32_t dur = now - s_b2DownAt;
      s_b2IsDown = false;
      s_b2DownAt = 0;
      Serial.printf("[BTN] BTN2 released %lu ms\n", static_cast<unsigned long>(dur));
      if (!s_inMenu && !s_menuEnterArmed && !s_ignoreNextB2Release && dur >= 40 &&
          dur <= kShortPressMaxMs && onAutoShortPress != nullptr) {
        onAutoShortPress();
      }
      s_menuEnterArmed = false;
      s_ignoreNextB2Release = false;
    }
  }

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

  if (s_b2Armed && b2Down && !s_inMenu && !s_menuEnterArmed && s_b2DownAt != 0 &&
      (now - s_b2DownAt) >= kMenuEnterHoldMs) {
    s_inMenu = true;
    s_item = 0;
    s_menuEnterArmed = true;
    s_ignoreNextB2Release = true;
    s_menuPrevB1 = b1Down;
    s_menuPrevB2 = b2Down;
    Serial.println("[MENU] enter (hold BTN2)");
  }
}
