// firmware/src/ultrasonic.h
#pragma once

#include <Arduino.h>

void ultrasonicInit();
float ultrasonicGetDistanceCm();
// Milliseconds since the last echo. A large value means the sensor has not answered.
uint32_t ultrasonicEchoAgeMs();
