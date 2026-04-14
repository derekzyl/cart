// firmware/src/webserver.h
#pragma once

#include <Arduino.h>
#include <IPAddress.h>

void webserverInit();
void webserverBroadcastTelemetry();

bool webserverWifiUsingSta();
IPAddress webserverRobotIp();
void webserverRefreshRobotIp();
