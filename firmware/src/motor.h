// firmware/src/motor.h
#pragma once

#include <Arduino.h>
#include <stdint.h>

void motorInit();
void motorSteerLeft(uint8_t pwm);
void motorSteerRight(uint8_t pwm);
void motorSteerCenter();
void motorEnable();
void motorDisable();
