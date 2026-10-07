#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

#include "config.h"

void steerInit();
void steerTick(uint32_t nowMs);
void steerSetEnabled(bool enabled);
void steerSetCommandScale(float fraction);

// Dial / playback target in degrees. scalePot limits stick travel; playback does not.
void steerCommandAngle(float deg, bool scalePot);
void steerStraight();
void steerRecentre();
void steerHold();

float steerAngleDeg();
SteerCmd steerDirection();
int16_t steerAngleTenths();
// True while the steering motor is moving or pausing between directions.
bool steerMotorBusy();

// Fills a reply JSON object. Returns true when the caller should send it.
bool steerHandleCommand(JsonDocument &doc, JsonDocument &reply);
