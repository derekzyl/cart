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

/// Remember the name used for the next save / load. Empty becomes "route".
void routeNoteName(const char *name);
const char *routeActiveName();
/// "name1|name2" of saved routes. Pointer is stable until the next call.
const char *routeLibraryCsv();
bool routeDeleteNamed(const char *name);
bool routeLoadNamed(const char *name);

void routeTickRecord(uint32_t nowMs, DriveCmd d, int16_t steerDegX10, bool motorsActive);
void routeTickPlay(uint32_t nowMs, DriveCmd &outDrive, float &outAngleDeg, bool &haveAngle,
                   bool &isPlaying);

RouteFsm routeGetState();
uint16_t routeGetCurrentIndex();
uint16_t routeGetTotalSteps();
