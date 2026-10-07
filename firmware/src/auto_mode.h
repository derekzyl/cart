#pragma once

#include <Arduino.h>

#include "config.h"

void autoModeInit();
void autoModeReset();
void autoModeTick(uint32_t nowMs, float distCm, DriveCmd &outDrive, float &outAngleDeg,
                  bool &wantStraight, uint8_t &outForwardPercent);
AutoFsm autoModeGetFsm();
