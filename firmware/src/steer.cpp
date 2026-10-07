#include "steer.h"

#include <Preferences.h>
#include <math.h>
#include <string.h>

enum class MoveFsm : uint8_t { Idle, MovingRight, MovingLeft, DeadTime };
enum class HomeFsm : uint8_t { None, ToStop, Dead, Back };

struct SteerCalib {
  float rightDegPerSec;
  float leftDegPerSec;
  uint32_t fullTravelMs;
  float minAngleDeg;
  float maxAngleDeg;
  float centreTrimDeg;
  uint32_t deadTimeMs;
  uint8_t restBothOn;
  uint8_t relayActiveLow;
  float straightDeadbandDeg;
};

static SteerCalib s_cal;
static float s_angle = 0.0f;
static float s_target = 0.0f;
static float s_angleAtStart = 0.0f;
static float s_committed = 0.0f;
// Wheel position in degrees from center, negative left, positive right.
static float s_mech = 0.0f;
static float s_mechGoal = 0.0f;
// Milliseconds run to the right (positive) or left (negative) since center.
// This is the wheel position. Degrees are only a label for it.
static int32_t s_sideMs = 0;
static int32_t s_sideAtStart = 0;
static uint32_t s_commitMs = 0;
static float s_mechAtStart = 0.0f;
static float s_shownAtStart = 0.0f;
static float s_shownTarget = 0.0f;
static float s_scale = 1.0f;
static uint32_t s_phaseStart = 0;
static uint32_t s_deadUntil = 0;
static MoveFsm s_fsm = MoveFsm::Idle;
static MoveFsm s_afterDead = MoveFsm::Idle;
static HomeFsm s_home = HomeFsm::None;
static bool s_enabled = false;
static bool s_bootHome = true;
static bool s_measuring = false;
static bool s_measureRight = true;
static uint32_t s_measureStart = 0;
static uint32_t s_lastMeasureMs = 0;

static portMUX_TYPE s_cmdMux = portMUX_INITIALIZER_UNLOCKED;
enum class Pending : uint8_t { None, Angle, AngleRaw, Straight, Recentre, Hold, Jog, MeasureStart, MeasureStop };
static Pending s_pending = Pending::None;
static float s_pendingDeg = 0.0f;
static bool s_pendingRight = true;
static uint32_t s_pendingMs = 0;
static float s_pendingSpan = 0.0f;

static float wrap360(float a) {
  while (a < 0.0f) {
    a += 360.0f;
  }
  while (a >= 360.0f) {
    a -= 360.0f;
  }
  return a;
}

static float signedDelta(float from, float to) {
  float d = wrap360(to) - wrap360(from);
  if (d > 180.0f) {
    d -= 360.0f;
  }
  if (d < -180.0f) {
    d += 360.0f;
  }
  return d;
}

static bool fullCircle() {
  return (s_cal.maxAngleDeg - s_cal.minAngleDeg) >= 359.0f;
}

static bool windowWraps() {
  return !fullCircle() && s_cal.minAngleDeg > s_cal.maxAngleDeg;
}

// Right stick is 0°–90° (wheel right). Left stick is 270°–360° (wheel left).
// 0° and 180° are straight. Forward and reverse do not change the side.
static bool mapMech() {
  return !fullCircle();
}

static float lockDeg() {
  if (windowWraps()) {
    return (s_cal.maxAngleDeg + (360.0f - s_cal.minAngleDeg)) * 0.5f;
  }
  return fabsf(s_cal.maxAngleDeg - s_cal.minAngleDeg) * 0.5f;
}

static float shownAngle() {
  return wrap360(s_angle + s_cal.centreTrimDeg);
}

static void setShown(float shown) {
  s_angle = wrap360(shown - s_cal.centreTrimDeg);
}

// A command is degrees from center, not a compass heading. Negative is left.
static float commandToMech(float deg) {
  float s = signedDelta(0.0f, deg);
  float lock = lockDeg();
  if (lock < 1.0f) {
    lock = 30.0f;
  }
  if (s > lock) {
    s = lock;
  }
  if (s < -lock) {
    s = -lock;
  }
  return s;
}

static void clampSideMs() {
  const int32_t cap = static_cast<int32_t>(s_cal.fullTravelMs / 2);
  if (s_sideMs > cap) {
    s_sideMs = cap;
  }
  if (s_sideMs < -cap) {
    s_sideMs = -cap;
  }
}

static int32_t halfMs() {
  int32_t h = static_cast<int32_t>(s_cal.fullTravelMs / 2);
  if (h < 40) {
    h = 40;
  }
  return h;
}

static int32_t mechToMs(float mech) {
  float lock = lockDeg();
  if (lock < 1.0f) {
    lock = 30.0f;
  }
  float ms = (mech / lock) * static_cast<float>(halfMs());
  const float cap = static_cast<float>(halfMs());
  if (ms > cap) {
    ms = cap;
  }
  if (ms < -cap) {
    ms = -cap;
  }
  return static_cast<int32_t>(ms);
}

static void syncMechFromTime() {
  float lock = lockDeg();
  if (lock < 1.0f) {
    lock = 30.0f;
  }
  const float half = static_cast<float>(halfMs());
  s_mech = half > 1.0f ? (static_cast<float>(s_sideMs) / half) * lock : 0.0f;
}

static float mechFromShown(float shown) {
  return commandToMech(shown);
}

static float shownFromMech(float mech) {
  float lock = lockDeg();
  if (lock < 1.0f) {
    return 0.0f;
  }
  float n = mech / lock;
  if (n > 1.0f) {
    n = 1.0f;
  }
  if (n < -1.0f) {
    n = -1.0f;
  }
  return wrap360(asinf(n) * (180.0f / PI));
}

static void clampMech() {
  const float lock = lockDeg();
  if (s_mech > lock) {
    s_mech = lock;
  }
  if (s_mech < -lock) {
    s_mech = -lock;
  }
}

static bool inWindow(float deg) {
  deg = wrap360(deg);
  if (fullCircle()) {
    return true;
  }
  if (windowWraps()) {
    return deg >= s_cal.minAngleDeg || deg <= s_cal.maxAngleDeg;
  }
  return deg >= s_cal.minAngleDeg && deg <= s_cal.maxAngleDeg;
}

static float clampRange(float deg) {
  deg = wrap360(deg);
  if (inWindow(deg)) {
    return deg;
  }
  const float toMin = fabsf(signedDelta(deg, s_cal.minAngleDeg));
  const float toMax = fabsf(signedDelta(deg, s_cal.maxAngleDeg));
  return toMin <= toMax ? wrap360(s_cal.minAngleDeg) : wrap360(s_cal.maxAngleDeg);
}

static void writeRelay(int pin, bool energized) {
  bool high = energized;
  if (s_cal.relayActiveLow != 0) {
    high = !energized;
  }
  digitalWrite(pin, high ? HIGH : LOW);
}

static void steerRest() {
  const bool on = s_cal.restBothOn != 0;
  writeRelay(PIN_STEER_RELAY_RIGHT, on);
  writeRelay(PIN_STEER_RELAY_LEFT, on);
}

static void steerRight() {
  // The pin named LEFT turns this wheel to the right.
  writeRelay(PIN_STEER_RELAY_RIGHT, false);
  writeRelay(PIN_STEER_RELAY_LEFT, true);
}

static void steerLeft() {
  writeRelay(PIN_STEER_RELAY_RIGHT, true);
  writeRelay(PIN_STEER_RELAY_LEFT, false);
}

static SteerCalib defaults() {
  SteerCalib c;
  c.rightDegPerSec = STEER_RIGHT_DEG_PER_SEC;
  c.leftDegPerSec = STEER_LEFT_DEG_PER_SEC;
  c.fullTravelMs = STEER_FULL_TRAVEL_MS;
  c.minAngleDeg = STEER_MIN_ANGLE_DEG;
  c.maxAngleDeg = STEER_MAX_ANGLE_DEG;
  c.centreTrimDeg = STEER_CENTRE_TRIM_DEG;
  c.deadTimeMs = STEER_DEADTIME_MS;
  c.restBothOn = STEER_REST_BOTH_ON ? 1 : 0;
  c.relayActiveLow = RELAY_ACTIVE_LOW ? 1 : 0;
  c.straightDeadbandDeg = STEER_STRAIGHT_DEADBAND_DEG;
  return c;
}

static void sanitize(SteerCalib *c) {
  if (c->rightDegPerSec < 150.0f) {
    c->rightDegPerSec = 150.0f;
  }
  if (c->leftDegPerSec < 150.0f) {
    c->leftDegPerSec = 150.0f;
  }
  if (c->rightDegPerSec > 720.0f) {
    c->rightDegPerSec = 720.0f;
  }
  if (c->leftDegPerSec > 720.0f) {
    c->leftDegPerSec = 720.0f;
  }
  if (c->fullTravelMs < 160) {
    c->fullTravelMs = 160;
  }
  if (c->fullTravelMs > 400) {
    c->fullTravelMs = 400;
  }
  if (c->deadTimeMs < 20) {
    c->deadTimeMs = 20;
  }
  if (c->deadTimeMs > 200) {
    c->deadTimeMs = 200;
  }
  if (c->straightDeadbandDeg < 0.5f) {
    c->straightDeadbandDeg = 0.5f;
  }
  if (c->straightDeadbandDeg > 25.0f) {
    c->straightDeadbandDeg = 25.0f;
  }
  if (c->minAngleDeg < 0.0f) {
    c->minAngleDeg = 0.0f;
  }
  if (c->maxAngleDeg < 0.0f) {
    c->maxAngleDeg = 0.0f;
  }
  if (c->minAngleDeg > 360.0f) {
    c->minAngleDeg = 360.0f;
  }
  if (c->maxAngleDeg > 360.0f) {
    c->maxAngleDeg = 360.0f;
  }
  if (fabsf(c->maxAngleDeg - c->minAngleDeg) < 1.0f) {
    c->minAngleDeg = STEER_MIN_ANGLE_DEG;
    c->maxAngleDeg = STEER_MAX_ANGLE_DEG;
  }
}

static void loadCalib() {
  s_cal = defaults();
  Preferences prefs;
  if (!prefs.begin("cart_steer", true)) {
    return;
  }
  if (prefs.getBytesLength("cal2") == sizeof(SteerCalib)) {
    prefs.getBytes("cal2", &s_cal, sizeof(SteerCalib));
    sanitize(&s_cal);
  }
  prefs.end();
}

static void saveCalib() {
  sanitize(&s_cal);
  Preferences prefs;
  if (prefs.begin("cart_steer", false)) {
    prefs.putBytes("cal2", &s_cal, sizeof(s_cal));
    prefs.end();
  }
}

static void fillReply(JsonDocument &reply) {
  reply["cmd"] = "calib";
  reply["angle"] = steerAngleDeg();
  reply["right_dps"] = s_cal.rightDegPerSec;
  reply["left_dps"] = s_cal.leftDegPerSec;
  reply["full_travel_ms"] = s_cal.fullTravelMs;
  reply["min_deg"] = s_cal.minAngleDeg;
  reply["max_deg"] = s_cal.maxAngleDeg;
  reply["centre_trim"] = s_cal.centreTrimDeg;
  reply["dead_time_ms"] = s_cal.deadTimeMs;
  reply["rest_both_on"] = s_cal.restBothOn != 0;
  reply["relay_active_low"] = s_cal.relayActiveLow != 0;
  reply["deadband_deg"] = s_cal.straightDeadbandDeg;
  reply["measure_ms"] = s_lastMeasureMs;
}

static float rateFor(MoveFsm dir) {
  float r = dir == MoveFsm::MovingRight ? s_cal.rightDegPerSec : s_cal.leftDegPerSec;
  if (r < 1.0f) {
    r = 1.0f;
  }
  return r;
}

static void integrate(uint32_t now) {
  if (s_fsm != MoveFsm::MovingRight && s_fsm != MoveFsm::MovingLeft) {
    return;
  }
  const float elapsed = static_cast<float>(now - s_phaseStart) / 1000.0f;
  const float moved = rateFor(s_fsm) * elapsed;
  const float signedMove = s_fsm == MoveFsm::MovingRight ? moved : -moved;
  if (mapMech()) {
    const uint32_t elapsedMs = now - s_phaseStart;
    const bool done = s_commitMs == 0 || elapsedMs >= s_commitMs;
    const int32_t used = done ? static_cast<int32_t>(s_commitMs) : static_cast<int32_t>(elapsedMs);
    if (s_fsm == MoveFsm::MovingRight) {
      s_sideMs = s_sideAtStart + used;
    } else {
      s_sideMs = s_sideAtStart - used;
    }
    clampSideMs();
    syncMechFromTime();
    setShown(s_mech);
    if (done) {
      steerRest();
      s_fsm = MoveFsm::Idle;
      s_committed = 0.0f;
      s_commitMs = 0;
    }
    return;
  }
  if (fabsf(signedMove) >= fabsf(s_committed)) {
    s_angle = wrap360(s_angleAtStart + s_committed);
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_committed = 0.0f;
    return;
  }
  s_angle = wrap360(s_angleAtStart + signedMove);
}

static void beginDead(uint32_t now, MoveFsm next, float target, float delta) {
  steerRest();
  s_target = target;
  s_committed = delta;
  s_afterDead = next;
  s_deadUntil = now + s_cal.deadTimeMs;
  s_fsm = MoveFsm::DeadTime;
}

static void startMove(uint32_t now, MoveFsm dir, float target, float delta, uint32_t commitMs = 0) {
  if (!s_enabled) {
    steerRest();
    s_fsm = MoveFsm::Idle;
    return;
  }
  s_home = HomeFsm::None;
  s_target = target;
  s_committed = delta;
  s_sideAtStart = s_sideMs;
  if (commitMs > 0) {
    s_commitMs = commitMs;
  } else {
    const float rate = rateFor(dir);
    uint32_t derived = static_cast<uint32_t>(fabsf(delta) / rate * 1000.0f);
    if (derived == 0 && fabsf(delta) > 0.2f) {
      derived = 1;
    }
    s_commitMs = derived;
  }
  s_angleAtStart = s_angle;
  s_phaseStart = now;
  s_fsm = dir;
  if (dir == MoveFsm::MovingRight) {
    steerRight();
  } else {
    steerLeft();
  }
}

static void requestTarget(uint32_t now, float logicalDeg, bool ignoreSmall) {
  integrate(now);
  if (mapMech()) {
    const float mechGoal = commandToMech(logicalDeg);
    const int32_t goalMs = mechToMs(mechGoal);
    int32_t deltaMs = goalMs - s_sideMs;
    const int32_t cap = halfMs();
    const int32_t full = cap * 2;
    if (deltaMs > full) {
      deltaMs = full;
    }
    if (deltaMs < -full) {
      deltaMs = -full;
    }
    // A move back toward center stops a little early, so a fast motor
    // cannot run through center into the opposite stop.
    const int32_t magGoal = goalMs < 0 ? -goalMs : goalMs;
    const int32_t magSide = s_sideMs < 0 ? -s_sideMs : s_sideMs;
    if (magGoal + 8 < magSide) {
      deltaMs = static_cast<int32_t>(static_cast<float>(deltaMs) * 0.9f);
    }
    const float lock = lockDeg() < 1.0f ? 30.0f : lockDeg();
    const int32_t minMs = static_cast<int32_t>((STEER_MIN_MOVE_DEG / lock) * static_cast<float>(cap));
    const int32_t deadMs =
        static_cast<int32_t>((s_cal.straightDeadbandDeg / lock) * static_cast<float>(cap));
    const bool idle = s_fsm != MoveFsm::MovingRight && s_fsm != MoveFsm::MovingLeft &&
                      s_fsm != MoveFsm::DeadTime;
    const int32_t stepMs = deltaMs < 0 ? -deltaMs : deltaMs;
    if (ignoreSmall && idle && stepMs < minMs) {
      return;
    }
    if (stepMs <= deadMs) {
      steerRest();
      s_fsm = MoveFsm::Idle;
      s_sideMs = goalMs;
      s_mechGoal = mechGoal;
      syncMechFromTime();
      setShown(s_mech);
      s_target = s_angle;
      s_commitMs = 0;
      return;
    }
    const MoveFsm want = deltaMs > 0 ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
    const uint32_t pulse = static_cast<uint32_t>(deltaMs < 0 ? -deltaMs : deltaMs);
    if ((s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) && s_fsm == want &&
        fabsf(s_mechGoal - mechGoal) < 0.4f) {
      return;
    }
    s_mechGoal = mechGoal;
    s_shownTarget = wrap360(mechGoal);
    s_shownAtStart = shownAngle();
    s_mechAtStart = s_mech;
    const float stored = s_shownTarget;
    const float delta = static_cast<float>(deltaMs);
    if (s_fsm == want) {
      s_sideAtStart = s_sideMs;
      s_phaseStart = now;
      s_committed = delta;
      s_commitMs = pulse;
      s_target = stored;
      return;
    }
    if (s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) {
      beginDead(now, want, stored, delta);
      s_commitMs = pulse;
      return;
    }
    if (s_fsm == MoveFsm::DeadTime) {
      s_target = stored;
      s_committed = delta;
      s_commitMs = pulse;
      s_afterDead = want;
      return;
    }
    startMove(now, want, stored, delta, pulse);
    return;
  }
  float target = wrap360(logicalDeg - s_cal.centreTrimDeg);
  if (!fullCircle()) {
    target = clampRange(target);
  }
  const float delta = signedDelta(s_angle, target);
  const bool idle = s_fsm != MoveFsm::MovingRight && s_fsm != MoveFsm::MovingLeft &&
                    s_fsm != MoveFsm::DeadTime;
  if (ignoreSmall && idle && fabsf(delta) < STEER_MIN_MOVE_DEG) {
    return;
  }
  if (fabsf(delta) <= s_cal.straightDeadbandDeg) {
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_target = s_angle;
    return;
  }
  const MoveFsm want = delta > 0.0f ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
  if ((s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) &&
      fabsf(signedDelta(s_target, target)) < 0.5f && s_fsm == want) {
    return;
  }
  if (s_fsm == want) {
    s_angleAtStart = s_angle;
    s_phaseStart = now;
    s_committed = delta;
    s_target = target;
    return;
  }
  if (s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) {
    beginDead(now, want, target, delta);
    return;
  }
  if (s_fsm == MoveFsm::DeadTime) {
    s_target = target;
    s_committed = delta;
    s_afterDead = want;
    return;
  }
  startMove(now, want, target, delta);
}

static void requestStraight(uint32_t now) {
  integrate(now);
  if (mapMech()) {
    if (fabsf(s_mech) <= s_cal.straightDeadbandDeg) {
      steerRest();
      s_fsm = MoveFsm::Idle;
      s_home = HomeFsm::None;
      s_mech = 0.0f;
      s_sideMs = 0;
      setShown(0.0f);
      return;
    }
    requestTarget(now, 0.0f, false);
    return;
  }
  const float shown = shownAngle();
  const float d0 = fabsf(signedDelta(shown, 0.0f));
  if (d0 <= s_cal.straightDeadbandDeg) {
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    setShown(0.0f);
    return;
  }
  requestTarget(now, 0.0f, false);
}

static void beginHome(uint32_t now) {
  if (!s_enabled) {
    s_bootHome = true;
    return;
  }
  s_home = HomeFsm::ToStop;
  s_phaseStart = now;
  s_fsm = MoveFsm::MovingRight;
  s_committed = 10000.0f;
  s_angleAtStart = s_angle;
  s_mechAtStart = s_mech;
  steerRight();
}

static void tickHome(uint32_t now) {
  if (s_home == HomeFsm::None) {
    return;
  }
  const uint32_t elapsed = now - s_phaseStart;
  if (s_home == HomeFsm::ToStop) {
    const float moved = rateFor(MoveFsm::MovingRight) * (static_cast<float>(elapsed) / 1000.0f);
    if (mapMech()) {
      s_mech = s_mechAtStart + moved;
      clampMech();
      setShown(shownFromMech(s_mech));
    } else {
      s_angle = wrap360(s_angleAtStart + moved);
    }
    const uint32_t over = s_cal.fullTravelMs + (s_cal.fullTravelMs / 6);
    if (elapsed >= over) {
      steerRest();
      s_home = HomeFsm::Dead;
      s_phaseStart = now;
      s_fsm = MoveFsm::DeadTime;
    }
    return;
  }
  if (s_home == HomeFsm::Dead) {
    if (elapsed >= s_cal.deadTimeMs) {
      s_home = HomeFsm::Back;
      s_phaseStart = now;
      s_angleAtStart = s_angle;
      s_mechAtStart = s_mech;
      s_fsm = MoveFsm::MovingLeft;
      steerLeft();
    }
    return;
  }
  const float moved = rateFor(MoveFsm::MovingLeft) * (static_cast<float>(elapsed) / 1000.0f);
  if (mapMech()) {
    s_mech = s_mechAtStart - moved;
    clampMech();
    setShown(shownFromMech(s_mech));
  } else {
    s_angle = wrap360(s_angleAtStart - moved);
  }
  // fullTravelMs is stop-to-stop. From the right stop, half of that is center.
  const uint32_t backMs = s_cal.fullTravelMs / 2;
  if (elapsed >= backMs) {
    steerRest();
    s_mech = 0.0f;
    s_sideMs = 0;
    setShown(0.0f);
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    s_committed = 0.0f;
  }
}

static void queue(Pending kind, float deg, bool right, uint32_t ms, float span) {
  portENTER_CRITICAL(&s_cmdMux);
  s_pending = kind;
  s_pendingDeg = deg;
  s_pendingRight = right;
  s_pendingMs = ms;
  s_pendingSpan = span;
  portEXIT_CRITICAL(&s_cmdMux);
}

void steerInit() {
  loadCalib();
  pinMode(PIN_STEER_RELAY_RIGHT, OUTPUT);
  pinMode(PIN_STEER_RELAY_LEFT, OUTPUT);
  steerRest();
  s_enabled = false;
  s_bootHome = true;
  s_fsm = MoveFsm::Idle;
  s_mech = 0.0f;
  s_angle = wrap360(0.0f - s_cal.centreTrimDeg);
}

void steerSetEnabled(bool enabled) {
  if (!enabled) {
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    s_measuring = false;
    s_enabled = false;
    return;
  }
  const bool was = s_enabled;
  s_enabled = true;
  if (!was && s_bootHome) {
    s_bootHome = false;
    beginHome(millis());
  }
}

void steerSetCommandScale(float fraction) {
  if (fraction < STEER_POT_MIN) {
    fraction = STEER_POT_MIN;
  }
  if (fraction > STEER_POT_MAX) {
    fraction = STEER_POT_MAX;
  }
  s_scale = fraction;
}

void steerCommandAngle(float deg, bool scalePot) {
  if (scalePot) {
    float off = signedDelta(0.0f, deg);
    off *= s_scale;
    deg = wrap360(off);
  }
  queue(scalePot ? Pending::Angle : Pending::AngleRaw, deg, true, 0, 0.0f);
}

void steerStraight() {
  queue(Pending::Straight, 0.0f, true, 0, 0.0f);
}

void steerRecentre() {
  queue(Pending::Recentre, 0.0f, true, 0, 0.0f);
}

void steerHold() {
  queue(Pending::Hold, 0.0f, true, 0, 0.0f);
}

float steerAngleDeg() {
  if (mapMech()) {
    return wrap360(s_mech);
  }
  return wrap360(s_angle + s_cal.centreTrimDeg);
}

bool steerMotorBusy() {
  return s_home != HomeFsm::None || s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft ||
         s_fsm == MoveFsm::DeadTime;
}

SteerCmd steerDirection() {
  if (mapMech()) {
    if (fabsf(s_mech) <= s_cal.straightDeadbandDeg) {
      return SteerCmd::Center;
    }
    return s_mech > 0.0f ? SteerCmd::Right : SteerCmd::Left;
  }
  const float shown = steerAngleDeg();
  if (fabsf(signedDelta(shown, 0.0f)) <= s_cal.straightDeadbandDeg ||
      fabsf(signedDelta(shown, 180.0f)) <= s_cal.straightDeadbandDeg) {
    return SteerCmd::Center;
  }
  return signedDelta(0.0f, shown) > 0.0f ? SteerCmd::Right : SteerCmd::Left;
}

int16_t steerAngleTenths() {
  int v = static_cast<int>(lroundf(steerAngleDeg() * 10.0f));
  if (v < 0) {
    v = 0;
  }
  if (v > 3600) {
    v = 3600;
  }
  return static_cast<int16_t>(v);
}

void steerTick(uint32_t now) {
  Pending cmd = Pending::None;
  float deg = 0.0f;
  bool right = true;
  uint32_t ms = 0;
  float span = 0.0f;
  portENTER_CRITICAL(&s_cmdMux);
  cmd = s_pending;
  deg = s_pendingDeg;
  right = s_pendingRight;
  ms = s_pendingMs;
  span = s_pendingSpan;
  s_pending = Pending::None;
  portEXIT_CRITICAL(&s_cmdMux);

  if (!s_enabled) {
    if (cmd == Pending::Recentre) {
      s_bootHome = true;
    }
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    s_measuring = false;
    return;
  }
  if (cmd == Pending::Hold) {
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    s_measuring = false;
  }

  if (cmd == Pending::Recentre) {
    beginHome(now);
  } else if (cmd == Pending::Straight) {
    s_home = HomeFsm::None;
    requestStraight(now);
  } else if (cmd == Pending::Angle || cmd == Pending::AngleRaw) {
    s_home = HomeFsm::None;
    s_measuring = false;
    requestTarget(now, deg, cmd == Pending::Angle);
  } else if (cmd == Pending::Jog) {
    s_home = HomeFsm::None;
    s_measuring = false;
    if (ms == 0 || !s_enabled) {
      integrate(now);
      steerRest();
      s_fsm = MoveFsm::Idle;
    } else if (mapMech()) {
      integrate(now);
      const float rate = right ? s_cal.rightDegPerSec : s_cal.leftDegPerSec;
      const float delta = (right ? 1.0f : -1.0f) * rate * (static_cast<float>(ms) / 1000.0f);
      float goal = s_mech + delta;
      const float lock = lockDeg();
      if (goal > lock) {
        goal = lock;
      }
      if (goal < -lock) {
        goal = -lock;
      }
      const float mechDelta = goal - s_mech;
      const float shownTarget = shownFromMech(goal);
      if (fabsf(mechDelta) <= 0.2f) {
        steerRest();
        s_fsm = MoveFsm::Idle;
        s_mech = goal;
        setShown(shownTarget);
      } else {
        const MoveFsm dir = mechDelta > 0.0f ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
        s_shownTarget = shownTarget;
        s_shownAtStart = shownAngle();
        s_mechAtStart = s_mech;
        const float stored = wrap360(shownTarget - s_cal.centreTrimDeg);
        const uint32_t pulse = static_cast<uint32_t>(fabsf(mechDelta) / rate * 1000.0f);
        if (s_fsm == dir) {
          s_sideAtStart = s_sideMs;
          s_phaseStart = now;
          s_committed = mechDelta;
          s_commitMs = pulse == 0 ? 1 : pulse;
          s_target = stored;
        } else if (s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) {
          beginDead(now, dir, stored, mechDelta);
          s_commitMs = pulse == 0 ? 1 : pulse;
        } else if (s_fsm != MoveFsm::DeadTime) {
          startMove(now, dir, stored, mechDelta, pulse == 0 ? 1 : pulse);
        } else {
          s_target = stored;
          s_committed = mechDelta;
          s_commitMs = pulse == 0 ? 1 : pulse;
          s_afterDead = dir;
        }
      }
    } else {
      const float rate = right ? s_cal.rightDegPerSec : s_cal.leftDegPerSec;
      const float delta = (right ? 1.0f : -1.0f) * rate * (static_cast<float>(ms) / 1000.0f);
      const MoveFsm dir = right ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
      if (s_fsm == MoveFsm::MovingRight || s_fsm == MoveFsm::MovingLeft) {
        if (s_fsm != dir) {
          integrate(now);
          beginDead(now, dir, wrap360(s_angle + delta), delta);
        } else {
          s_angleAtStart = s_angle;
          s_phaseStart = now;
          s_committed = delta;
          s_target = wrap360(s_angle + delta);
        }
      } else if (s_fsm != MoveFsm::DeadTime) {
        startMove(now, dir, wrap360(s_angle + delta), delta);
      }
    }
  } else if (cmd == Pending::MeasureStart && s_enabled) {
    s_home = HomeFsm::None;
    s_measuring = true;
    s_measureRight = right;
    s_measureStart = now;
    s_angleAtStart = s_angle;
    s_mechAtStart = s_mech;
    s_phaseStart = now;
    s_committed = right ? 10000.0f : -10000.0f;
    s_fsm = right ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
    if (right) {
      steerRight();
    } else {
      steerLeft();
    }
  } else if (cmd == Pending::MeasureStop && s_measuring) {
    const uint32_t elapsed = now - s_measureStart;
    s_lastMeasureMs = elapsed;
    const float sec = static_cast<float>(elapsed) / 1000.0f;
    float useSpan = span;
    if (useSpan < 1.0f) {
      if (windowWraps()) {
        useSpan = s_cal.maxAngleDeg + (360.0f - s_cal.minAngleDeg);
      } else {
        useSpan = fabsf(s_cal.maxAngleDeg - s_cal.minAngleDeg);
      }
    }
    if (sec > 0.05f) {
      const float dps = useSpan / sec;
      if (s_measureRight) {
        s_cal.rightDegPerSec = dps;
      } else {
        s_cal.leftDegPerSec = dps;
      }
      sanitize(&s_cal);
    }
    if (mapMech()) {
      const float rate = s_measureRight ? s_cal.rightDegPerSec : s_cal.leftDegPerSec;
      const float moved = rate * sec;
      s_mech = s_mechAtStart + (s_measureRight ? moved : -moved);
      clampMech();
      s_sideMs = mechToMs(s_mech);
      setShown(shownFromMech(s_mech));
    } else {
      integrate(now);
    }
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_committed = 0.0f;
    s_measuring = false;
  }

  if (s_home != HomeFsm::None) {
    tickHome(now);
    return;
  }

  if (s_fsm == MoveFsm::DeadTime) {
    if (static_cast<int32_t>(now - s_deadUntil) >= 0) {
      const MoveFsm dir = s_afterDead;
      if (mapMech()) {
        const uint32_t pulse = s_commitMs;
        if (pulse == 0 || dir == MoveFsm::Idle) {
          steerRest();
          s_fsm = MoveFsm::Idle;
          syncMechFromTime();
          setShown(s_mech);
        } else {
          const MoveFsm want = s_committed >= 0.0f ? MoveFsm::MovingRight : MoveFsm::MovingLeft;
          startMove(now, want, s_target, s_committed, pulse);
        }
      } else {
        const float delta = signedDelta(s_angle, s_target);
        if (fabsf(delta) <= s_cal.straightDeadbandDeg || dir == MoveFsm::Idle) {
          steerRest();
          s_fsm = MoveFsm::Idle;
        } else {
          startMove(now, dir, s_target, delta);
        }
      }
    }
    return;
  }

  if (s_measuring) {
    const float elapsed = static_cast<float>(now - s_phaseStart) / 1000.0f;
    const float moved = rateFor(s_fsm) * elapsed;
    if (mapMech()) {
      s_mech = s_mechAtStart + (s_fsm == MoveFsm::MovingRight ? moved : -moved);
      clampMech();
      setShown(shownFromMech(s_mech));
    } else {
      s_angle = wrap360(s_angleAtStart + (s_fsm == MoveFsm::MovingRight ? moved : -moved));
    }
    return;
  }

  integrate(now);
}

bool steerHandleCommand(JsonDocument &doc, JsonDocument &reply) {
  const char *cmd = doc["cmd"] | "";
  bool respond = false;
  if (strcmp(cmd, "steer_angle") == 0) {
    steerCommandAngle(doc["angle"] | 0.0f, true);
  } else if (strcmp(cmd, "straight") == 0) {
    steerStraight();
  } else if (strcmp(cmd, "recentre") == 0) {
    steerRecentre();
    respond = true;
  } else if (strcmp(cmd, "get_calib") == 0) {
    respond = true;
  } else if (strcmp(cmd, "set_calib") == 0) {
    if (doc["right_dps"].is<float>() || doc["right_dps"].is<int>()) {
      s_cal.rightDegPerSec = doc["right_dps"].as<float>();
    }
    if (doc["left_dps"].is<float>() || doc["left_dps"].is<int>()) {
      s_cal.leftDegPerSec = doc["left_dps"].as<float>();
    }
    if (doc["full_travel_ms"].is<int>() || doc["full_travel_ms"].is<float>()) {
      s_cal.fullTravelMs = doc["full_travel_ms"].as<uint32_t>();
    }
    if (doc["min_deg"].is<float>() || doc["min_deg"].is<int>()) {
      s_cal.minAngleDeg = doc["min_deg"].as<float>();
    }
    if (doc["max_deg"].is<float>() || doc["max_deg"].is<int>()) {
      s_cal.maxAngleDeg = doc["max_deg"].as<float>();
    }
    if (doc["centre_trim"].is<float>() || doc["centre_trim"].is<int>()) {
      s_cal.centreTrimDeg = doc["centre_trim"].as<float>();
    }
    if (doc["dead_time_ms"].is<int>() || doc["dead_time_ms"].is<float>()) {
      s_cal.deadTimeMs = doc["dead_time_ms"].as<uint32_t>();
    }
    if (doc["rest_both_on"].is<bool>()) {
      s_cal.restBothOn = doc["rest_both_on"].as<bool>() ? 1 : 0;
    }
    if (doc["relay_active_low"].is<bool>()) {
      s_cal.relayActiveLow = doc["relay_active_low"].as<bool>() ? 1 : 0;
    }
    if (doc["deadband_deg"].is<float>() || doc["deadband_deg"].is<int>()) {
      s_cal.straightDeadbandDeg = doc["deadband_deg"].as<float>();
    }
    sanitize(&s_cal);
    respond = true;
  } else if (strcmp(cmd, "calib_jog") == 0) {
    const char *dir = doc["dir"] | "right";
    const uint32_t dur = doc["duration_ms"] | 0;
    queue(Pending::Jog, 0.0f, strcmp(dir, "left") != 0, dur, 0.0f);
  } else if (strcmp(cmd, "calib_measure_start") == 0) {
    const char *dir = doc["dir"] | "right";
    queue(Pending::MeasureStart, 0.0f, strcmp(dir, "left") != 0, 0, 0.0f);
    respond = true;
  } else if (strcmp(cmd, "calib_measure_stop") == 0) {
    queue(Pending::MeasureStop, 0.0f, true, 0, doc["span_deg"] | 0.0f);
    respond = true;
  } else if (strcmp(cmd, "calib_set_centre") == 0) {
    s_angle = wrap360(0.0f - s_cal.centreTrimDeg);
    s_mech = 0.0f;
    s_sideMs = 0;
    steerRest();
    s_fsm = MoveFsm::Idle;
    s_home = HomeFsm::None;
    respond = true;
  } else if (strcmp(cmd, "calib_save") == 0) {
    saveCalib();
    respond = true;
  } else if (strcmp(cmd, "calib_reset_defaults") == 0) {
    s_cal = defaults();
    saveCalib();
    respond = true;
  } else if (strcmp(cmd, "steer") == 0) {
    const char *dir = doc["dir"] | "center";
    const float pwm = static_cast<float>(doc["pwm"] | 0);
    if (strcmp(dir, "center") == 0 || pwm <= 0.0f) {
      steerStraight();
    } else {
      const float mag = (pwm / 255.0f) * 180.0f;
      steerCommandAngle(strcmp(dir, "left") == 0 ? wrap360(-mag) : mag, true);
    }
  }
  if (respond) {
    fillReply(reply);
  }
  return respond;
}
