// firmware/src/auto_mode.h
#pragma once

#include <Arduino.h>

#include "config.h"

void autoModeInit();
void autoModeReset();
void autoModeTick(uint32_t nowMs, float distCm, DriveCmd &outDrive, SteerCmd &outSteer,
                  uint8_t &outSteerPwm, uint8_t &outForwardPercent);
AutoFsm autoModeGetFsm();
