// firmware/src/buzzer.h
#pragma once

#include <Arduino.h>

void buzzerInit();
void buzzerSetMuted(bool muted);
void buzzerTick(uint32_t nowMs, float distCm, bool forceOff);
