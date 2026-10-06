// firmware/src/display.h
#pragma once

#include <Arduino.h>

#include "config.h"

void displayInit();
void displayShowWifiReady();
void displayShowMenu(const char *line1, const char *line2);
void displayRedrawHardware();
void displayForceReinit();
void displayAfterNetworkUp();
void displayShowWaiting();
void displayShowConnecting(const char *ssid, uint32_t elapsedMs, uint32_t timeoutMs);
void displayShowNormal(uint8_t steerPwm, DriveCmd drive, float distCm, float sensitivity,
                       bool wsConnected, bool motorEnabled, bool autoMode);
void displayShowAuto(float distCm, AutoFsm autoState);
void displayShowRecording(uint16_t steps);
void displayShowPlayback(uint16_t idx, uint16_t total, float distCm, bool reverse);
void displayUpdate();
