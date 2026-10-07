// firmware/src/leds.cpp
#include "leds.h"
#include "config.h"

static bool s_headlightUser = false;

static inline void ledWrite(int pin, bool lit) {
  if (LED_GPIO_ACTIVE_LOW) {
    digitalWrite(pin, lit ? LOW : HIGH);
  } else {
    digitalWrite(pin, lit ? HIGH : LOW);
  }
}

void ledsInit() {
  pinMode(PIN_LED_LEFT, OUTPUT);
  pinMode(PIN_LED_RIGHT, OUTPUT);
  pinMode(PIN_LED_HEADLIGHT, OUTPUT);
  ledWrite(PIN_LED_LEFT, false);
  ledWrite(PIN_LED_RIGHT, false);
  ledWrite(PIN_LED_HEADLIGHT, false);
}

void ledsSetNavEnabled(bool enabled) {
  (void)enabled;
}

void ledsSetHeadlight(bool on) {
  s_headlightUser = on;
}

void ledsTick(uint32_t nowMs, bool navEnabled, SteerCmd steer, bool routeRecording,
              bool forceAllOff) {
  if (forceAllOff) {
    ledWrite(PIN_LED_LEFT, false);
    ledWrite(PIN_LED_RIGHT, false);
    ledWrite(PIN_LED_HEADLIGHT, false);
    return;
  }

  const uint32_t phase = nowMs % (INDICATOR_BLINK_HALF_MS * 2);
  const bool blinkOn = phase < INDICATOR_BLINK_HALF_MS;

  bool leftOn = false;
  bool rightOn = false;

  if (navEnabled && steer != SteerCmd::Center) {
    if (steer == SteerCmd::Left) {
      leftOn = blinkOn;
    } else if (steer == SteerCmd::Right) {
      rightOn = blinkOn;
    }
  }

  ledWrite(PIN_LED_LEFT, leftOn);
  ledWrite(PIN_LED_RIGHT, rightOn);

  if (routeRecording) {
    const uint32_t hp = nowMs % (RECORD_HEADLIGHT_HALF_MS * 2);
    ledWrite(PIN_LED_HEADLIGHT, hp < RECORD_HEADLIGHT_HALF_MS);
  } else {
    ledWrite(PIN_LED_HEADLIGHT, s_headlightUser);
  }
}
