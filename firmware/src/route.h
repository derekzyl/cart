// firmware/src/route.h
#pragma once

#include <Arduino.h>

#include "config.h"

void routeInit();

bool routeStartRecording();
bool routeStopRecording();
bool routeStartPlayback(bool reverse);
void routeStopFromCommand();

/// Erase stored route steps (idle only; stops playback first).
void routeClearMemory();

void routeTickRecord(uint32_t nowMs, DriveCmd d, int16_t steerSigned, bool motorsActive);
void routeTickPlay(uint32_t nowMs, float sensitivity, DriveCmd &outDrive, SteerCmd &outSteer,
                   uint8_t &outPwm, bool &isPlaying);

RouteFsm routeGetState();
uint16_t routeGetCurrentIndex();
uint16_t routeGetTotalSteps();
