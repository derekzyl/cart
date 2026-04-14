// firmware/src/route.cpp
#include "route.h"
#include "config.h"

#include <esp32-hal-psram.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static void routeStopPlaybackInternal();

static RouteStep *s_steps = nullptr;
static size_t s_count = 0;
static RouteFsm s_state = RouteFsm::Idle;

static uint32_t s_lastRecordMs = 0;
static uint32_t s_playStepStartMs = 0;
static size_t s_playIndex = 0;
static bool s_reversePlay = false;

static void freeSteps() {
  if (s_steps != nullptr) {
    free(s_steps);
    s_steps = nullptr;
  }
  s_count = 0;
}

void routeInit() {
  if (s_steps == nullptr) {
    if (psramFound()) {
      s_steps = static_cast<RouteStep *>(
          ps_malloc(ROUTE_MAX_STEPS * sizeof(RouteStep)));
    }
    if (s_steps == nullptr) {
      s_steps = static_cast<RouteStep *>(malloc(ROUTE_MAX_STEPS * sizeof(RouteStep)));
    }
  }
  if (s_steps != nullptr) {
    memset(s_steps, 0, ROUTE_MAX_STEPS * sizeof(RouteStep));
  }
  s_count = 0;
  s_state = RouteFsm::Idle;
  s_lastRecordMs = 0;
  s_playStepStartMs = 0;
  s_playIndex = 0;
  s_reversePlay = false;
}

static void pushOrMerge(uint8_t drive, int16_t steer, uint32_t addMs) {
  if (s_steps == nullptr) {
    return;
  }
  if (s_count == 0) {
    s_steps[0].drive = drive;
    s_steps[0].steer_pwm = steer;
    s_steps[0].duration_ms = addMs;
    s_count = 1;
    return;
  }
  RouteStep &last = s_steps[s_count - 1];
  if (last.drive == drive && last.steer_pwm == steer) {
    last.duration_ms += addMs;
    return;
  }
  if (s_count >= ROUTE_MAX_STEPS) {
    return;
  }
  RouteStep &n = s_steps[s_count];
  n.drive = drive;
  n.steer_pwm = steer;
  n.duration_ms = addMs;
  s_count += 1;
}

bool routeStartRecording() {
  routeStopPlaybackInternal();
  s_count = 0;
  s_lastRecordMs = millis();
  s_state = RouteFsm::Recording;
  return s_steps != nullptr;
}

bool routeStopRecording() {
  if (s_state != RouteFsm::Recording) {
    return false;
  }
  pushOrMerge(0, 0, 1);
  s_state = RouteFsm::Idle;
  s_lastRecordMs = 0;
  return true;
}

bool routeStartPlayback(bool reverse) {
  if (s_steps == nullptr || s_count == 0) {
    return false;
  }
  s_reversePlay = reverse;
  s_state = reverse ? RouteFsm::PlayingReverse : RouteFsm::Playing;
  s_playIndex = reverse ? (s_count - 1) : 0;
  s_playStepStartMs = millis();
  return true;
}

static void routeStopPlaybackInternal() {
  s_state = RouteFsm::Idle;
  s_playIndex = 0;
  s_playStepStartMs = 0;
  s_reversePlay = false;
}

void routeStopFromCommand() {
  routeStopPlaybackInternal();
}

void routeClearMemory() {
  routeStopPlaybackInternal();
  s_state = RouteFsm::Idle;
  s_lastRecordMs = 0;
  s_playIndex = 0;
  s_playStepStartMs = 0;
  s_reversePlay = false;
  s_count = 0;
  if (s_steps != nullptr) {
    memset(s_steps, 0, ROUTE_MAX_STEPS * sizeof(RouteStep));
  }
}

static uint8_t flipDrive(uint8_t d) {
  if (d == 1) {
    return 2;
  }
  if (d == 2) {
    return 1;
  }
  return 0;
}

static void decodeStep(const RouteStep &st, bool reverse, DriveCmd &outD, SteerCmd &outS,
                       uint8_t &outPwm) {
  uint8_t d = st.drive;
  int16_t sp = st.steer_pwm;
  if (reverse) {
    d = flipDrive(d);
    sp = static_cast<int16_t>(-sp);
  }

  if (d == 1) {
    outD = DriveCmd::Forward;
  } else if (d == 2) {
    outD = DriveCmd::Reverse;
  } else {
    outD = DriveCmd::Stop;
  }

  if (sp < 0) {
    outS = SteerCmd::Left;
    int m = -static_cast<int>(sp);
    if (m > 255) {
      m = 255;
    }
    outPwm = static_cast<uint8_t>(m);
  } else if (sp > 0) {
    outS = SteerCmd::Right;
    int m = static_cast<int>(sp);
    if (m > 255) {
      m = 255;
    }
    outPwm = static_cast<uint8_t>(m);
  } else {
    outS = SteerCmd::Center;
    outPwm = 0;
  }
}

static void applySensitivitySteer(SteerCmd &st, uint8_t &pwm, float sensitivity) {
  if (pwm == 0 || st == SteerCmd::Center) {
    return;
  }
  float m = static_cast<float>(pwm) * sensitivity;
  int im = static_cast<int>(lroundf(m));
  if (im > 255) {
    im = 255;
  }
  if (im < 0) {
    im = 0;
  }
  pwm = static_cast<uint8_t>(im);
}

void routeTickRecord(uint32_t nowMs, DriveCmd d, int16_t steerSigned, bool motorsActive) {
  if (s_state != RouteFsm::Recording || s_steps == nullptr) {
    return;
  }
  if (!motorsActive) {
    return;
  }
  if (nowMs - s_lastRecordMs < ROUTE_SAMPLE_MS) {
    return;
  }
  s_lastRecordMs = nowMs;

  uint8_t enc = 0;
  if (d == DriveCmd::Forward) {
    enc = 1;
  } else if (d == DriveCmd::Reverse) {
    enc = 2;
  }
  pushOrMerge(enc, steerSigned, ROUTE_SAMPLE_MS);
}

void routeTickPlay(uint32_t nowMs, float sensitivity, DriveCmd &outDrive, SteerCmd &outSteer,
                   uint8_t &outPwm, bool &isPlaying) {
  isPlaying = false;
  if (s_state != RouteFsm::Playing && s_state != RouteFsm::PlayingReverse) {
    return;
  }
  if (s_steps == nullptr || s_count == 0) {
    routeStopPlaybackInternal();
    return;
  }

  isPlaying = true;

  if (s_playStepStartMs == 0) {
    s_playStepStartMs = nowMs;
  }

  const RouteStep &cur = s_steps[s_playIndex];
  const uint32_t elapsed = nowMs - s_playStepStartMs;
  if (elapsed >= cur.duration_ms) {
    if (s_reversePlay) {
      if (s_playIndex == 0) {
        routeStopPlaybackInternal();
        isPlaying = false;
        outDrive = DriveCmd::Stop;
        outSteer = SteerCmd::Center;
        outPwm = 0;
        return;
      }
      s_playIndex -= 1;
    } else {
      s_playIndex += 1;
      if (s_playIndex >= s_count) {
        routeStopPlaybackInternal();
        isPlaying = false;
        outDrive = DriveCmd::Stop;
        outSteer = SteerCmd::Center;
        outPwm = 0;
        return;
      }
    }
    s_playStepStartMs = nowMs;
  }

  const RouteStep &active = s_steps[s_playIndex];
  decodeStep(active, s_reversePlay, outDrive, outSteer, outPwm);
  applySensitivitySteer(outSteer, outPwm, sensitivity);
}

RouteFsm routeGetState() {
  return s_state;
}

uint16_t routeGetCurrentIndex() {
  if (s_state != RouteFsm::Playing && s_state != RouteFsm::PlayingReverse) {
    return 0;
  }
  return static_cast<uint16_t>(s_playIndex + 1);
}

uint16_t routeGetTotalSteps() {
  return static_cast<uint16_t>(s_count);
}
