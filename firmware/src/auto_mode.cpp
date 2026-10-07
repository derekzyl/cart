#include "auto_mode.h"
#include "config.h"

static AutoFsm s_fsm = AutoFsm::Forward;
static uint32_t s_phaseStartMs = 0;
static bool s_avoidLeft = true;

void autoModeInit() {
  autoModeReset();
}

void autoModeReset() {
  s_fsm = AutoFsm::Forward;
  s_phaseStartMs = 0;
  s_avoidLeft = true;
}

AutoFsm autoModeGetFsm() {
  return s_fsm;
}

void autoModeTick(uint32_t nowMs, float distCm, DriveCmd &outDrive, float &outAngleDeg,
                  bool &wantStraight, uint8_t &outForwardPercent) {
  outDrive = DriveCmd::Stop;
  outAngleDeg = 0.0f;
  wantStraight = false;
  outForwardPercent = 0;

  if (s_phaseStartMs == 0) {
    s_phaseStartMs = nowMs;
  }

  switch (s_fsm) {
    case AutoFsm::Forward: {
      wantStraight = true;
      if (distCm >= 0.0f && distCm < 20.0f) {
        s_avoidLeft = !s_avoidLeft;
        s_fsm = AutoFsm::AvoidTurn;
        s_phaseStartMs = nowMs;
        break;
      }
      if (distCm > 40.0f || distCm < 0.0f) {
        outForwardPercent = 100;
        outDrive = DriveCmd::Forward;
      } else if (distCm >= 20.0f) {
        outForwardPercent = 40;
        outDrive = DriveCmd::Forward;
      } else {
        outDrive = DriveCmd::Stop;
      }
      break;
    }
    case AutoFsm::AvoidTurn: {
      outDrive = DriveCmd::Stop;
      outAngleDeg = s_avoidLeft ? 315.0f : 45.0f;
      if (nowMs - s_phaseStartMs >= AUTO_AVOID_TURN_MS) {
        s_fsm = AutoFsm::AvoidForward;
        s_phaseStartMs = nowMs;
      }
      break;
    }
    case AutoFsm::AvoidForward: {
      outAngleDeg = s_avoidLeft ? 315.0f : 45.0f;
      if (distCm >= 0.0f && distCm < 20.0f) {
        s_avoidLeft = !s_avoidLeft;
        s_fsm = AutoFsm::AvoidTurn;
        s_phaseStartMs = nowMs;
        break;
      }
      if (nowMs - s_phaseStartMs < AUTO_AVOID_FORWARD_MS) {
        outForwardPercent = 60;
        outDrive = DriveCmd::Forward;
      } else {
        s_fsm = AutoFsm::Resume;
        s_phaseStartMs = nowMs;
      }
      break;
    }
    case AutoFsm::Resume: {
      outDrive = DriveCmd::Stop;
      wantStraight = true;
      if (nowMs - s_phaseStartMs >= AUTO_RESUME_STEER_MS) {
        s_fsm = AutoFsm::Forward;
        s_phaseStartMs = nowMs;
      }
      break;
    }
    default:
      s_fsm = AutoFsm::Forward;
      break;
  }
}
