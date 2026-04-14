// firmware/src/leds.h
#pragma once

#include <Arduino.h>

#include "config.h"

void ledsInit();
void ledsSetNavEnabled(bool enabled);
void ledsSetHeadlight(bool on);
void ledsTick(uint32_t nowMs, bool navEnabled, SteerCmd steer, uint8_t steerPwm,
              bool routeRecording, bool forceAllOff);
