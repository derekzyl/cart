// firmware/src/main.cpp
#include <Arduino.h>
#include <math.h>
#include <stdio.h>

#include "auto_mode.h"
#include "board_menu.h"
#include "buzzer.h"
#include "config.h"
#include "display.h"
#include "leds.h"
#include "motor.h"
#include "relay.h"
#include "route.h"
#include "steer.h"
#include "ultrasonic.h"
#include "webserver.h"

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

SemaphoreHandle_t g_stateMutex = nullptr;
SharedRobotState g_state{};

static int s_potSamples[POT_ADC_SAMPLES];
static int s_potIndex = 0;
static int s_potCount = 0;

static bool s_btn1LastRaw = true;
static uint32_t s_btn1LastChangeMs = 0;
static bool s_btn1Stable = true;

static uint32_t s_fwdPctWindowStart = 0;

static char s_notice1[17];
static char s_notice2[17];
static uint32_t s_noticeUntilMs = 0;

static void lcdNotice(const char *line1, const char *line2) {
  snprintf(s_notice1, sizeof(s_notice1), "%s", line1);
  snprintf(s_notice2, sizeof(s_notice2), "%s", line2);
  s_noticeUntilMs = millis() + 1800;
  displayRush();
}

static bool lcdNoticeActive(uint32_t now) {
  return s_noticeUntilMs != 0 && static_cast<int32_t>(s_noticeUntilMs - now) > 0;
}

static float readPotSensitivity() {
  if (s_potCount < POT_ADC_SAMPLES) {
    return STEER_POT_MIN;
  }
  int64_t sum = 0;
  for (int i = 0; i < POT_ADC_SAMPLES; ++i) {
    sum += s_potSamples[i];
  }
  const int avg = static_cast<int>(sum / POT_ADC_SAMPLES);
  float t = (avg - static_cast<float>(POT_ADC_MIN)) /
            static_cast<float>(POT_ADC_MAX - POT_ADC_MIN);
  if (t < 0.0f) {
    t = 0.0f;
  }
  if (t > 1.0f) {
    t = 1.0f;
  }
  return STEER_POT_MIN + t * (STEER_POT_MAX - STEER_POT_MIN);
}

static void onBootPressed();
static void onButton1Pressed();
static void onButton2Pressed();

static void serviceOneButton(uint32_t now, bool rawPressed, bool &seenHigh, bool &candidate,
                             uint32_t &changeAt, bool &stablePressed, uint32_t &downAt,
                             bool &resetTriggered, void (*onPress)(), const char *name,
                             const char *holdLine2) {
  if (!rawPressed) {
    seenHigh = true;
  }
  if (rawPressed != candidate) {
    candidate = rawPressed;
    changeAt = now;
  } else if ((now - changeAt) >= BUTTON_DEBOUNCE_MS && rawPressed != stablePressed) {
    stablePressed = rawPressed;
    if (stablePressed) {
      downAt = now;
      resetTriggered = false;
      Serial.printf("[BTN] %s pressed\n", name);
      if (onPress != nullptr) {
        onPress();
      }
    } else {
      downAt = 0;
      Serial.printf("[BTN] %s released\n", name);
    }
  }
  if (seenHigh && stablePressed && !resetTriggered && downAt != 0 && (now - downAt) >= 3000) {
    resetTriggered = true;
    Serial.printf("[BTN] %s hold 3s -> hotspot reset\n", name);
    buzzerBeep(180);
    webserverResetToHotspot();
    lcdNotice("HOTSPOT RESET", holdLine2);
  }
}

static void serviceButtons(uint32_t now) {
  // Active-low: idle is HIGH (10k to 3.3V), press is LOW.
  // Ignore a pin until it has been seen released, so a stuck-low input
  // cannot reset the hotspot a couple of seconds after boot.
  static bool bootSeenHigh = false;
  static bool bootCandidate = false;
  static uint32_t bootChangeAt = 0;
  static bool bootStable = false;
  static uint32_t bootDownAt = 0;
  static bool bootReset = false;

  static bool b1SeenHigh = false;
  static bool b1Candidate = false;
  static uint32_t b1ChangeAt = 0;
  static bool b1Stable = false;
  static uint32_t b1DownAt = 0;
  static bool b1Reset = false;

  serviceOneButton(now, digitalRead(PIN_BUTTON_BOOT) == LOW, bootSeenHigh, bootCandidate,
                   bootChangeAt, bootStable, bootDownAt, bootReset, onBootPressed, "BOOT",
                   "BOOT hold 3s");

  serviceOneButton(now, buttonDriveIsPressed(), b1SeenHigh, b1Candidate,
                   b1ChangeAt, b1Stable, b1DownAt, b1Reset, onButton1Pressed, "BTN1",
                   "BTN1 hold 3s");

  boardMenuTick(now, onButton2Pressed);
}


static void onBootPressed() {
  lcdNotice("BOOT BTN", "hold 3s = reset");
}

static void onButton1Pressed() {
  if (boardMenuIsActive()) {
    return;
  }
  if (!takeStateMutex()) {
    return;
  }
  g_state.motorEnabled = !g_state.motorEnabled;
  const bool on = g_state.motorEnabled;
  giveStateMutex();
  Serial.printf("[BTN1] motor enable -> %u\n", on ? 1U : 0U);
  lcdNotice(on ? "MTR ENABLED" : "MTR DISABLED", "BTN1 pressed");
}

static void onButton2Pressed() {
  if (!takeStateMutex()) {
    return;
  }
  g_state.autoMode = !g_state.autoMode;
  if (g_state.autoMode) {
    g_state.pendingRoute = PendingRouteAction::Stop;
  }
  const bool on = g_state.autoMode;
  Serial.printf("[BTN] auto -> %u\n", on ? 1U : 0U);
  giveStateMutex();
  lcdNotice(on ? "AUTO ON" : "AUTO OFF", "BTN2 pressed");
}

static void relayForwardPercent(uint8_t percent, uint32_t nowMs, bool active) {
  if (!active || percent == 0) {
    driveStop();
    s_fwdPctWindowStart = 0;
    return;
  }
  if (percent >= 100) {
    driveForward();
    s_fwdPctWindowStart = 0;
    return;
  }
  if (s_fwdPctWindowStart == 0) {
    s_fwdPctWindowStart = nowMs;
  }
  const uint32_t period = ULTRASONIC_TIMER_PERIOD_MS;
  const uint32_t phase = (nowMs - s_fwdPctWindowStart) % period;
  const uint32_t onTime = (period * static_cast<uint32_t>(percent)) / 100U;
  if (phase < onTime) {
    driveForward();
  } else {
    driveStop();
  }
}

static void applyManualDrive(DriveCmd d) {
  switch (d) {
    case DriveCmd::Forward:
      driveForward();
      break;
    case DriveCmd::Reverse:
      driveReverse();
      break;
    case DriveCmd::Stop:
    default:
      driveStop();
      break;
  }
}

static void consumePendingRoute() {
  PendingRouteAction a = PendingRouteAction::None;
  char name[13];
  name[0] = '\0';
  if (takeStateMutex()) {
    a = g_state.pendingRoute;
    g_state.pendingRoute = PendingRouteAction::None;
    strncpy(name, g_state.pendingRouteName, 12);
    name[12] = '\0';
    giveStateMutex();
  }
  switch (a) {
    case PendingRouteAction::RecordStart:
      routeNoteName(name);
      routeStartRecording();
      break;
    case PendingRouteAction::RecordStop:
      routeNoteName(name);
      routeStopRecording();
      break;
    case PendingRouteAction::Playback:
      if (name[0] != '\0') {
        routeLoadNamed(name);
      }
      routeStartPlayback(false);
      break;
    case PendingRouteAction::PlaybackReverse:
      if (name[0] != '\0') {
        routeLoadNamed(name);
      }
      routeStartPlayback(true);
      break;
    case PendingRouteAction::Stop:
      if (routeGetState() == RouteFsm::Recording) {
        routeStopRecording();
      }
      routeStopFromCommand();
      break;
    case PendingRouteAction::ClearMemory:
      routeClearMemory();
      break;
    case PendingRouteAction::DeleteNamed:
      routeDeleteNamed(name);
      break;
    case PendingRouteAction::None:
    default:
      break;
  }
}

static void taskWebCore0(void *param) {
  (void)param;
  for (;;) {
    webserverBroadcastTelemetry();
    vTaskDelay(pdMS_TO_TICKS(TELEMETRY_INTERVAL_MS));
  }
}

static void taskControlCore1(void *param) {
  (void)param;

  for (;;) {
    const uint32_t now = millis();

    const float distCm = ultrasonicGetDistanceCm();

    const int potAdc = analogRead(PIN_POT_ADC);
    s_potSamples[s_potIndex] = potAdc;
    s_potIndex = (s_potIndex + 1) % POT_ADC_SAMPLES;
    if (s_potCount < POT_ADC_SAMPLES) {
      s_potCount += 1;
    }

    const float sensitivity = readPotSensitivity();

    serviceButtons(now);

    consumePendingRoute();

    if (boardMenuIsActive()) {
      motorDisable();
      driveStop();
      steerHold();
      steerSetEnabled(false);
      steerTick(now);
      relayForwardPercent(0, now, false);
      ledsTick(now, false, SteerCmd::Center, false, true);
      buzzerTick(now, distCm, true);
      char menuL1[17];
      char menuL2[17];
      boardMenuGetLines(menuL1, menuL2);
      displayShowMenu(menuL1, menuL2);
      displayUpdate();
      vTaskDelay(pdMS_TO_TICKS(5));
      continue;
    }

    bool motorEnabled = false;
    bool autoMode = false;
    bool navLeds = false;
    bool headlight = false;
    bool buzzMute = false;
    bool watchdog = false;
    DriveCmd wsDrive = DriveCmd::Stop;
    int wsClients = 0;

    if (takeStateMutex()) {
      motorEnabled = g_state.motorEnabled;
      autoMode = g_state.autoMode;
      navLeds = g_state.navLedsEnabled;
      headlight = g_state.headlightOn;
      buzzMute = g_state.buzzerMuted;
      watchdog = g_state.watchdogTripped;
      wsDrive = g_state.driveCmd;
      wsClients = g_state.wsClientCount;
      giveStateMutex();
    }

    ledsSetHeadlight(headlight);
    buzzerSetMuted(buzzMute);
    steerSetCommandScale(sensitivity);

    const bool routePlaying =
        (routeGetState() == RouteFsm::Playing || routeGetState() == RouteFsm::PlayingReverse);
    const bool routeRecording = (routeGetState() == RouteFsm::Recording);

    DriveCmd appliedDrive = DriveCmd::Stop;
    uint8_t appliedFwdPct = 0;
    bool useRelayPercent = false;
    DriveCmd telemDrive = wsDrive;

    if (watchdog) {
      motorDisable();
      driveStop();
      steerHold();
      steerSetEnabled(false);
      relayForwardPercent(0, now, false);
      routeStopFromCommand();
      autoModeReset();
      ledsTick(now, navLeds, SteerCmd::Center, routeRecording, true);
      buzzerTick(now, distCm, true);
      telemDrive = DriveCmd::Stop;
    } else if (!motorEnabled) {
      motorDisable();
      driveStop();
      steerHold();
      steerSetEnabled(false);
      relayForwardPercent(0, now, false);
      ledsTick(now, navLeds, steerDirection(), routeRecording, false);
      buzzerTick(now, distCm, false);
      telemDrive = wsDrive;
    } else {
      motorEnable();
      steerSetEnabled(true);

      if (routePlaying) {
        bool playing = false;
        bool haveAngle = false;
        float playAngle = 0.0f;
        routeTickPlay(now, appliedDrive, playAngle, haveAngle, playing);
        if (playing && haveAngle) {
          steerCommandAngle(playAngle, false);
        }

        relayForwardPercent(0, now, false);
        applyManualDrive(appliedDrive);

        ledsTick(now, navLeds, steerDirection(), routeRecording, false);
        buzzerTick(now, distCm, false);
        telemDrive = appliedDrive;
      } else if (autoMode) {
        float autoAngle = 0.0f;
        bool wantStraight = false;
        autoModeTick(now, distCm, appliedDrive, autoAngle, wantStraight, appliedFwdPct);
        if (wantStraight) {
          steerStraight();
        } else {
          steerCommandAngle(autoAngle, false);
        }
        if (appliedFwdPct > 0 && appliedFwdPct < 100) {
          useRelayPercent = true;
        }

        if (useRelayPercent) {
          relayForwardPercent(appliedFwdPct, now, true);
        } else if (appliedDrive == DriveCmd::Forward && appliedFwdPct >= 100) {
          relayForwardPercent(100, now, true);
        } else {
          relayForwardPercent(0, now, false);
          applyManualDrive(appliedDrive);
        }

        ledsTick(now, navLeds, steerDirection(), routeRecording, false);
        buzzerTick(now, distCm, false);
        telemDrive = appliedDrive;
      } else {
        autoModeReset();
        relayForwardPercent(0, now, false);

        applyManualDrive(wsDrive);
        appliedDrive = wsDrive;
        telemDrive = wsDrive;

        ledsTick(now, navLeds, steerDirection(), routeRecording, false);
        buzzerTick(now, distCm, false);

        routeTickRecord(now, wsDrive, steerAngleTenths(), true);
      }
    }

    steerTick(now);
    // Steering and drive share the battery. While the wheel is shifting,
    // the forward/reverse relay stays off, then drive resumes.
    if (steerMotorBusy()) {
      driveStop();
      s_fwdPctWindowStart = 0;
    }

    if (takeStateMutex()) {
      const bool distLive = ultrasonicEchoAgeMs() < 1000;
      g_state.telemetryDistCm = distLive ? static_cast<int>(lroundf(distCm)) : -1;
      g_state.telemetrySteerAngle = steerAngleDeg();
      g_state.telemetrySteer = watchdog ? SteerCmd::Center : steerDirection();
      g_state.telemetryDrive = telemDrive;
      g_state.telemetryEnabled = motorEnabled && !watchdog;
      g_state.telemetryAuto = autoMode;
      g_state.telemetryNavLeds = navLeds;
      g_state.telemetryHeadlight = headlight;
      g_state.telemetryBuzzerMuted = buzzMute;
      g_state.telemetryBtn1 = buttonDriveIsPressed();
      g_state.telemetryBtn2 = (digitalRead(PIN_BUTTON_AUTO_MODE) == LOW);
      g_state.telemetrySensitivity = sensitivity;
      g_state.telemetryRouteState = routeGetState();
      g_state.telemetryRouteStep = routeGetCurrentIndex();
      g_state.telemetryRouteTotal = routeGetTotalSteps();
      giveStateMutex();
    }

    const RouteFsm rfsm = routeGetState();
    if (lcdNoticeActive(now)) {
      displayShowMenu(s_notice1, s_notice2);
    } else if (rfsm == RouteFsm::Recording) {
      displayShowRecording(routeGetTotalSteps());
    } else if (rfsm == RouteFsm::Playing) {
      displayShowPlayback(routeGetCurrentIndex(), routeGetTotalSteps(), distCm, false);
    } else if (rfsm == RouteFsm::PlayingReverse) {
      displayShowPlayback(routeGetCurrentIndex(), routeGetTotalSteps(), distCm, true);
    } else if (autoMode) {
      displayShowAuto(distCm, autoModeGetFsm());
    } else {
      displayShowNormal(static_cast<int>(lroundf(steerAngleDeg())), wsDrive, distCm, sensitivity,
                        wsClients > 0, motorEnabled, autoMode);
    }

    displayUpdate();
    vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  g_stateMutex = xSemaphoreCreateMutex();

  g_state.motorEnabled = false;
  g_state.autoMode = false;
  g_state.navLedsEnabled = false;
  g_state.headlightOn = false;
  g_state.buzzerMuted = false;
  g_state.watchdogTripped = false;
  g_state.driveCmd = DriveCmd::Stop;
  g_state.steerCmd = SteerCmd::Center;
  g_state.telemetrySteer = SteerCmd::Center;
  g_state.lastCommandedSpeedPwm = DEFAULT_COMMANDED_SPEED_PWM;
  g_state.lastWsMessageMs = millis();
  g_state.wsClientCount = 0;
  g_state.wifiReady = false;
  g_state.pendingRoute = PendingRouteAction::None;
  g_state.pendingRouteName[0] = '\0';

  // LCD first — I2C + backpack need a clean bus. Init after WiFi often finds no device / dead panel.
  
  displayInit();
  webserverInit();
  displayForceReinit();
  displayAfterNetworkUp();

  motorInit();
  steerInit();
  relayInit();
  ultrasonicInit();
  ledsInit();
  buzzerInit();
  routeInit();
  autoModeInit();

  pinMode(PIN_BUTTON_BOOT, INPUT_PULLUP);
  pinMode(PIN_BUTTON_DRIVE_ENABLE, INPUT_PULLUP);
  analogSetPinAttenuation(PIN_BUTTON_DRIVE_ENABLE, ADC_11db);
  // GPIO35 cannot use the internal pull-up; the 10k to 3.3V does that job.
  pinMode(PIN_BUTTON_AUTO_MODE, INPUT);
  boardMenuInit();

  xTaskCreatePinnedToCore(taskWebCore0, "web_ws", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(taskControlCore1, "control", 8192, nullptr, 4, nullptr, 1);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
