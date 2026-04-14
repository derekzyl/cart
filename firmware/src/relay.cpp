// firmware/src/relay.cpp
#include "relay.h"
#include "config.h"

void relayInit() {
  pinMode(PIN_RELAY_A, OUTPUT);
  pinMode(PIN_RELAY_B, OUTPUT);
  digitalWrite(PIN_RELAY_A, LOW);
  digitalWrite(PIN_RELAY_B, LOW);
}

void driveForward() {
  digitalWrite(PIN_RELAY_A, HIGH);
  digitalWrite(PIN_RELAY_B, LOW);
}

void driveReverse() {
  digitalWrite(PIN_RELAY_A, LOW);
  digitalWrite(PIN_RELAY_B, HIGH);
}

void driveStop() {
  digitalWrite(PIN_RELAY_A, LOW);
  digitalWrite(PIN_RELAY_B, LOW);
}
