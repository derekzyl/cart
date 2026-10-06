#pragma once

#include <Arduino.h>

void boardMenuInit();

bool boardMenuIsActive();
void boardMenuOpen();

/// Call each control-loop iteration after reading millis().
/// [onAutoShortPress] is invoked for a short BTN2 press when not entering menu.
void boardMenuTick(uint32_t now, void (*onAutoShortPress)());

/// Two 16-char lines for the LCD while menu is active.
void boardMenuGetLines(char line1[17], char line2[17]);
