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
}

static bool lcdNoticeActive(uint32_t now) {
  return s_noticeUntilMs != 0 && static_cast<int32_t>(s_noticeUntilMs - now) > 0;
}

static float readPotSensitivity() {
  if (s_potCount < POT_ADC_SAMPLES) {
    return STEER_SENSITIVITY_MIN;
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
  return STEER_SENSITIVITY_MIN + t * (STEER_SENSITIVITY_MAX - STEER_SENSITIVITY_MIN);
}

static uint32_t s_btn1DownAt = 0;
static bool s_btn1HoldArmed = false;

static void serviceButton(int pin, bool &lastRaw, uint32_t &lastChangeMs, bool &stable,
                          void (*onPressed)()) {
  const bool raw = digitalRead(pin) == HIGH;
  const uint32_t now = millis();
  if (raw != lastRaw) {
    lastRaw = raw;
    lastChangeMs = now;
  }
  if ((now - lastChangeMs) >= BUTTON_DEBOUNCE_MS && raw != stable) {
    stable = raw;
    if (!stable) {
      onPressed();
    }
  }
}

static void onButton1Pressed();

static void serviceButton1(uint32_t now) {
  const bool raw = digitalRead(PIN_BUTTON_DRIVE_ENABLE) == HIGH;
  if (raw != s_btn1LastRaw) {
    s_btn1LastRaw = raw;
    s_btn1LastChangeMs = now;
  }
  if ((now - s_btn1LastChangeMs) >= BUTTON_DEBOUNCE_MS && raw != s_btn1Stable) {
    s_btn1Stable = raw;
    if (!s_btn1Stable) {
      s_btn1DownAt = now;
      s_btn1HoldArmed = false;
    } else {
      if (s_btn1DownAt != 0 && !s_btn1HoldArmed) {
        onButton1Pressed();
      }
      s_btn1DownAt = 0;
      s_btn1HoldArmed = false;
    }
  }

  // Check 4-second hold on BTN1 outside menu to reset to hotspot
  if (!s_btn1Stable && s_btn1DownAt != 0 && !s_btn1HoldArmed) {
    if ((now - s_btn1DownAt) >= 4000) {
      s_btn1HoldArmed = true;
      Serial.println("[BTN1] 4s long hold: Resetting to Hotspot!");
      webserverResetToHotspot();
      lcdNotice("HOTSPOT RESET", "BTN1 long hold");
    }
  }
}

static void onButton1Pressed() {
  if (!takeStateMutex()) {
    return;
  }
  g_state.motorEnabled = !g_state.motorEnabled;
  const bool on = g_state.motorEnabled;
  Serial.printf("[BTN] enable -> %u\n", on ? 1U : 0U);
  giveStateMutex();
  lcdNotice(on ? "ENABLE ON" : "ENABLE OFF", "BTN1 pressed");
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

static uint8_t scaleSteerPwm(uint8_t raw, float sensitivity) {
  int out = static_cast<int>(lroundf(static_cast<float>(raw) * sensitivity));
  out = constrain(out, 0, 255);
  return static_cast<uint8_t>(out);
}

static int16_t steerSignedFromManual(SteerCmd s, uint8_t pwm) {
  if (pwm == 0 || s == SteerCmd::Center) {
    return 0;
  }
  if (s == SteerCmd::Left) {
    return static_cast<int16_t>(-static_cast<int16_t>(pwm));
  }
  return static_cast<int16_t>(pwm);
}

static void applySteering(SteerCmd s, uint8_t pwm) {
  const uint8_t p = pwm;
  if (p == 0 || s == SteerCmd::Center) {
    motorSteerCenter();
    return;
  }
  if (s == SteerCmd::Left) {
    motorSteerLeft(p);
  } else {
    motorSteerRight(p);
  }
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
  if (takeStateMutex()) {
    a = g_state.pendingRoute;
    g_state.pendingRoute = PendingRouteAction::None;
    giveStateMutex();
  }
  switch (a) {
    case PendingRouteAction::RecordStart:
      routeStartRecording();
      break;
    case PendingRouteAction::RecordStop:
      routeStopRecording();
      break;
    case PendingRouteAction::Playback:
      routeStartPlayback(false);
      break;
    case PendingRouteAction::PlaybackReverse:
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

    boardMenuTick(now, onButton2Pressed);
    if (!boardMenuIsActive()) {
      serviceButton1(now);
    }

    consumePendingRoute();

    if (boardMenuIsActive()) {
      motorDisable();
      driveStop();
      motorSteerCenter();
      relayForwardPercent(0, now, false);
      ledsTick(now, false, SteerCmd::Center, 0, false, true);
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
    bool navLeds = true;
    bool headlight = false;
    bool buzzMute = false;
    bool watchdog = false;
    DriveCmd wsDrive = DriveCmd::Stop;
    SteerCmd wsSteer = SteerCmd::Center;
    uint8_t wsSteerPwm = 0;
    int wsClients = 0;

    if (takeStateMutex()) {
      motorEnabled = g_state.motorEnabled;
      autoMode = g_state.autoMode;
      navLeds = g_state.navLedsEnabled;
      headlight = g_state.headlightOn;
      buzzMute = g_state.buzzerMuted;
      watchdog = g_state.watchdogTripped;
      wsDrive = g_state.driveCmd;
      wsSteer = g_state.steerCmd;
      wsSteerPwm = g_state.steerPwmRaw;
      wsClients = g_state.wsClientCount;
      giveStateMutex();
    }

    ledsSetHeadlight(headlight);
    buzzerSetMuted(buzzMute);

    const bool routePlaying =
        (routeGetState() == RouteFsm::Playing || routeGetState() == RouteFsm::PlayingReverse);
    const bool routeRecording = (routeGetState() == RouteFsm::Recording);

    DriveCmd appliedDrive = DriveCmd::Stop;
    SteerCmd appliedSteer = SteerCmd::Center;
    uint8_t appliedSteerPwm = 0;
    uint8_t appliedFwdPct = 0;
    bool useRelayPercent = false;
    DriveCmd telemDrive = wsDrive;

    if (watchdog) {
      motorDisable();
      driveStop();
      motorSteerCenter();
      relayForwardPercent(0, now, false);
      routeStopFromCommand();
      autoModeReset();
      ledsTick(now, navLeds, SteerCmd::Center, 0, routeRecording, true);
      buzzerTick(now, distCm, true);
      telemDrive = DriveCmd::Stop;
      appliedSteerPwm = 0;
    } else if (!motorEnabled) {
      motorDisable();
      driveStop();
      motorSteerCenter();
      relayForwardPercent(0, now, false);
      const uint8_t steerVis = scaleSteerPwm(wsSteerPwm, sensitivity);
      ledsTick(now, navLeds, wsSteer, steerVis, routeRecording, false);
      buzzerTick(now, distCm, false);
      telemDrive = wsDrive;
      appliedSteer = wsSteer;
      appliedSteerPwm = steerVis;
    } else {
      motorEnable();

      if (routePlaying) {
        bool playing = false;
        routeTickPlay(now, sensitivity, appliedDrive, appliedSteer, appliedSteerPwm, playing);
        (void)playing;

        relayForwardPercent(0, now, false);
        applyManualDrive(appliedDrive);
        applySteering(appliedSteer, appliedSteerPwm);

        ledsTick(now, navLeds, appliedSteer, appliedSteerPwm, routeRecording, false);
        buzzerTick(now, distCm, false);
        telemDrive = appliedDrive;
      } else if (autoMode) {
        autoModeTick(now, distCm, appliedDrive, appliedSteer, appliedSteerPwm, appliedFwdPct);
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

        const uint8_t scaledAutoSteer = scaleSteerPwm(appliedSteerPwm, sensitivity);
        applySteering(appliedSteer, scaledAutoSteer);

        ledsTick(now, navLeds, appliedSteer, scaledAutoSteer, routeRecording, false);
        buzzerTick(now, distCm, false);
        telemDrive = appliedDrive;
        appliedSteerPwm = scaledAutoSteer;
      } else {
        autoModeReset();
        relayForwardPercent(0, now, false);

        applyManualDrive(wsDrive);
        applySteering(wsSteer, scaleSteerPwm(wsSteerPwm, sensitivity));

        appliedDrive = wsDrive;
        appliedSteer = wsSteer;
        appliedSteerPwm = scaleSteerPwm(wsSteerPwm, sensitivity);
        telemDrive = wsDrive;

        ledsTick(now, navLeds, wsSteer, appliedSteerPwm, routeRecording, false);
        buzzerTick(now, distCm, false);

        const int16_t sig = steerSignedFromManual(wsSteer, wsSteerPwm);
        routeTickRecord(now, wsDrive, sig, true);
      }
    }

    const uint8_t telemSteer = watchdog ? 0 : appliedSteerPwm;

    if (takeStateMutex()) {
      g_state.telemetryDistCm = static_cast<int>(lroundf(distCm));
      g_state.telemetrySteerPwm = telemSteer;
      g_state.telemetryDrive = telemDrive;
      g_state.telemetryEnabled = motorEnabled && !watchdog;
      g_state.telemetryAuto = autoMode;
      g_state.telemetryNavLeds = navLeds;
      g_state.telemetryHeadlight = headlight;
      g_state.telemetryBuzzerMuted = buzzMute;
      g_state.telemetryBtn1 = (digitalRead(PIN_BUTTON_DRIVE_ENABLE) == LOW);
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
      displayShowNormal(scaleSteerPwm(wsSteerPwm, sensitivity), wsDrive, distCm, sensitivity,
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
  g_state.navLedsEnabled = true;
  g_state.headlightOn = false;
  g_state.buzzerMuted = false;
  g_state.watchdogTripped = false;
  g_state.driveCmd = DriveCmd::Stop;
  g_state.steerCmd = SteerCmd::Center;
  g_state.steerPwmRaw = 0;
  g_state.lastCommandedSpeedPwm = DEFAULT_COMMANDED_SPEED_PWM;
  g_state.lastWsMessageMs = millis();
  g_state.wsClientCount = 0;
  g_state.wifiReady = false;
  g_state.pendingRoute = PendingRouteAction::None;

  // LCD first — I2C + backpack need a clean bus. Init after WiFi often finds no device / dead panel.
  
  displayInit();
  webserverInit();
  displayAfterNetworkUp();

  motorInit();
  relayInit();
  ultrasonicInit();
  ledsInit();
  buzzerInit();
  routeInit();
  autoModeInit();

  pinMode(PIN_BUTTON_DRIVE_ENABLE, INPUT_PULLUP);
  // GPIO35 cannot use the internal pull-up; the 10k to 3.3V does that job.
  pinMode(PIN_BUTTON_AUTO_MODE, INPUT);
  boardMenuInit();

  xTaskCreatePinnedToCore(taskWebCore0, "web_ws", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(taskControlCore1, "control", 8192, nullptr, 4, nullptr, 1);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
