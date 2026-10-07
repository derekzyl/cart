// firmware/src/route.cpp
#include "route.h"
#include "config.h"

#include <Preferences.h>
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

static constexpr int kSlots = 6;
static constexpr int kNameLen = 12;
static constexpr size_t kSlotSteps = 64;

struct SavedRoute {
  char name[kNameLen + 1];
  uint16_t count;
  RouteStep steps[kSlotSteps];
};

static SavedRoute s_saved[kSlots];
static char s_activeName[kNameLen + 1] = "";
static char s_csv[kSlots * (kNameLen + 1) + 1] = "";

static void copyRouteName(char *dst, const char *src) {
  if (src == nullptr) {
    dst[0] = '\0';
    return;
  }
  size_t n = 0;
  while (src[n] != '\0' && n < kNameLen) {
    const char c = src[n];
    dst[n] = (c == '|' || c == ',') ? '_' : c;
    n += 1;
  }
  dst[n] = '\0';
}

static void rebuildCsv() {
  s_csv[0] = '\0';
  size_t used = 0;
  for (int i = 0; i < kSlots; ++i) {
    if (s_saved[i].name[0] == '\0') {
      continue;
    }
    const size_t len = strlen(s_saved[i].name);
    if (used > 0 && used + 1 < sizeof(s_csv)) {
      s_csv[used++] = '|';
    }
    if (used + len >= sizeof(s_csv)) {
      break;
    }
    memcpy(s_csv + used, s_saved[i].name, len);
    used += len;
    s_csv[used] = '\0';
  }
}

static int findSlot(const char *name) {
  for (int i = 0; i < kSlots; ++i) {
    if (s_saved[i].name[0] != '\0' && strcmp(s_saved[i].name, name) == 0) {
      return i;
    }
  }
  return -1;
}

static int emptySlot() {
  for (int i = 0; i < kSlots; ++i) {
    if (s_saved[i].name[0] == '\0') {
      return i;
    }
  }
  return -1;
}

static void persistLibrary() {
  uint8_t blob[kSlots * (13 + 2 + kSlotSteps * 5)];
  size_t at = 0;
  for (int i = 0; i < kSlots; ++i) {
    memcpy(blob + at, s_saved[i].name, 13);
    at += 13;
    const uint16_t count = s_saved[i].count;
    memcpy(blob + at, &count, 2);
    at += 2;
    for (size_t s = 0; s < kSlotSteps; ++s) {
      blob[at++] = s_saved[i].steps[s].drive;
      const int16_t steer = s_saved[i].steps[s].steer_deg_x10;
      memcpy(blob + at, &steer, 2);
      at += 2;
      uint32_t dur = s_saved[i].steps[s].duration_ms;
      if (dur > 65535U) {
        dur = 65535U;
      }
      const uint16_t d16 = static_cast<uint16_t>(dur);
      memcpy(blob + at, &d16, 2);
      at += 2;
    }
  }
  Preferences prefs;
  if (prefs.begin("cart_rt", false)) {
    prefs.putBytes("lib2", blob, at);
    prefs.end();
  }
  rebuildCsv();
}

static void loadLibrary() {
  memset(s_saved, 0, sizeof(s_saved));
  Preferences prefs;
  if (!prefs.begin("cart_rt", true)) {
    rebuildCsv();
    return;
  }
  const size_t expect = kSlots * (13 + 2 + kSlotSteps * 5);
  if (prefs.getBytesLength("lib2") == expect) {
    uint8_t blob[expect];
    prefs.getBytes("lib2", blob, expect);
    size_t at = 0;
    for (int i = 0; i < kSlots; ++i) {
      memcpy(s_saved[i].name, blob + at, 13);
      s_saved[i].name[kNameLen] = '\0';
      at += 13;
      uint16_t count = 0;
      memcpy(&count, blob + at, 2);
      at += 2;
      if (count > kSlotSteps) {
        count = kSlotSteps;
      }
      s_saved[i].count = count;
      for (size_t s = 0; s < kSlotSteps; ++s) {
        s_saved[i].steps[s].drive = blob[at++];
        int16_t steer = 0;
        memcpy(&steer, blob + at, 2);
        at += 2;
        uint16_t d16 = 0;
        memcpy(&d16, blob + at, 2);
        at += 2;
        s_saved[i].steps[s].steer_deg_x10 = steer;
        s_saved[i].steps[s].duration_ms = d16;
      }
    }
  }
  prefs.end();
  rebuildCsv();
}

static bool saveCurrentLocked(const char *name) {
  char cleaned[kNameLen + 1];
  copyRouteName(cleaned, name);
  if (cleaned[0] == '\0') {
    copyRouteName(cleaned, "route");
  }
  if (s_steps == nullptr || s_count == 0) {
    return false;
  }
  int slot = findSlot(cleaned);
  if (slot < 0) {
    slot = emptySlot();
  }
  if (slot < 0) {
    slot = 0;
  }
  memset(&s_saved[slot], 0, sizeof(s_saved[slot]));
  strncpy(s_saved[slot].name, cleaned, kNameLen);
  const size_t n = s_count < kSlotSteps ? s_count : kSlotSteps;
  s_saved[slot].count = static_cast<uint16_t>(n);
  memcpy(s_saved[slot].steps, s_steps, n * sizeof(RouteStep));
  strncpy(s_activeName, cleaned, kNameLen);
  persistLibrary();
  Serial.printf("[ROUTE] saved \"%s\" steps=%u\n", s_activeName, static_cast<unsigned>(n));
  return true;
}

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
  loadLibrary();
}

static void pushOrMerge(uint8_t drive, int16_t steer, uint32_t addMs) {
  if (s_steps == nullptr) {
    return;
  }
  if (s_count == 0) {
    s_steps[0].drive = drive;
    s_steps[0].steer_deg_x10 = steer;
    s_steps[0].duration_ms = addMs;
    s_count = 1;
    return;
  }
  RouteStep &last = s_steps[s_count - 1];
  if (last.drive == drive && last.steer_deg_x10 == steer) {
    last.duration_ms += addMs;
    return;
  }
  if (s_count >= ROUTE_MAX_STEPS) {
    return;
  }
  RouteStep &n = s_steps[s_count];
  n.drive = drive;
  n.steer_deg_x10 = steer;
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
  saveCurrentLocked(s_activeName);
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

static void decodeStep(const RouteStep &st, bool reverse, DriveCmd &outD, float &outAngle) {
  uint8_t d = st.drive;
  int tenths = static_cast<int>(st.steer_deg_x10);
  if (tenths < 0) {
    tenths = 0;
  }
  tenths %= 3600;
  if (reverse) {
    d = flipDrive(d);
    tenths = (3600 - tenths) % 3600;
  }
  if (d == 1) {
    outD = DriveCmd::Forward;
  } else if (d == 2) {
    outD = DriveCmd::Reverse;
  } else {
    outD = DriveCmd::Stop;
  }
  outAngle = static_cast<float>(tenths) / 10.0f;
}

void routeTickRecord(uint32_t nowMs, DriveCmd d, int16_t steerDegX10, bool motorsActive) {
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
  pushOrMerge(enc, steerDegX10, ROUTE_SAMPLE_MS);
}

void routeTickPlay(uint32_t nowMs, DriveCmd &outDrive, float &outAngleDeg, bool &haveAngle,
                   bool &isPlaying) {
  isPlaying = false;
  haveAngle = false;
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
        return;
      }
      s_playIndex -= 1;
    } else {
      s_playIndex += 1;
      if (s_playIndex >= s_count) {
        routeStopPlaybackInternal();
        isPlaying = false;
        outDrive = DriveCmd::Stop;
        return;
      }
    }
    s_playStepStartMs = nowMs;
  }

  const RouteStep &active = s_steps[s_playIndex];
  decodeStep(active, s_reversePlay, outDrive, outAngleDeg);
  haveAngle = true;
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

void routeNoteName(const char *name) {
  copyRouteName(s_activeName, name);
  if (s_activeName[0] == '\0') {
    copyRouteName(s_activeName, "route");
  }
}

const char *routeActiveName() {
  return s_activeName;
}

const char *routeLibraryCsv() {
  return s_csv;
}

bool routeLoadNamed(const char *name) {
  char cleaned[kNameLen + 1];
  copyRouteName(cleaned, name);
  const int slot = findSlot(cleaned);
  if (slot < 0 || s_steps == nullptr || s_saved[slot].count == 0) {
    return false;
  }
  routeStopPlaybackInternal();
  memset(s_steps, 0, ROUTE_MAX_STEPS * sizeof(RouteStep));
  s_count = s_saved[slot].count;
  memcpy(s_steps, s_saved[slot].steps, s_count * sizeof(RouteStep));
  strncpy(s_activeName, s_saved[slot].name, kNameLen);
  s_activeName[kNameLen] = '\0';
  Serial.printf("[ROUTE] loaded \"%s\" steps=%u\n", s_activeName, static_cast<unsigned>(s_count));
  return true;
}

bool routeDeleteNamed(const char *name) {
  char cleaned[kNameLen + 1];
  copyRouteName(cleaned, name);
  const int slot = findSlot(cleaned);
  if (slot < 0) {
    return false;
  }
  memset(&s_saved[slot], 0, sizeof(s_saved[slot]));
  if (strcmp(s_activeName, cleaned) == 0) {
    routeClearMemory();
    s_activeName[0] = '\0';
  }
  persistLibrary();
  Serial.printf("[ROUTE] deleted \"%s\"\n", cleaned);
  return true;
}
