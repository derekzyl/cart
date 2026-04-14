// firmware/src/buzzer.cpp
#include "buzzer.h"
#include "config.h"

static bool s_muted = false;

void buzzerInit() {
  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);
}

void buzzerSetMuted(bool muted) {
  s_muted = muted;
}

void buzzerTick(uint32_t nowMs, float distCm, bool forceOff) {
  if (forceOff || s_muted) {
    digitalWrite(PIN_BUZZER, LOW);
    return;
  }

  if (distCm > 40.0f) {
    digitalWrite(PIN_BUZZER, LOW);
    return;
  }

  if (distCm < 10.0f) {
    digitalWrite(PIN_BUZZER, HIGH);
    return;
  }

  uint32_t cycle = 0;
  uint32_t onMs = 100;

  if (distCm >= 20.0f) {
    cycle = 500;
  } else {
    cycle = 250;
  }

  const uint32_t pos = nowMs % cycle;
  const bool buzzOn = pos < onMs;
  digitalWrite(PIN_BUZZER, buzzOn ? HIGH : LOW);
}
