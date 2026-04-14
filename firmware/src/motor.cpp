// firmware/src/motor.cpp
#include "motor.h"
#include "config.h"

#include <driver/ledc.h>

static constexpr ledc_channel_t kLedcChR = LEDC_CHANNEL_0;
static constexpr ledc_channel_t kLedcChL = LEDC_CHANNEL_1;
static constexpr ledc_timer_bit_t kLedcDutyRes = LEDC_TIMER_8_BIT;

static void motorLedcAttachPin(int pin, ledc_channel_t channel) {
  ledc_channel_config_t ch = {};
  ch.gpio_num = static_cast<gpio_num_t>(pin);
  ch.speed_mode = LEDC_LOW_SPEED_MODE;
  ch.channel = channel;
  ch.intr_type = LEDC_INTR_DISABLE;
  ch.timer_sel = LEDC_TIMER_0;
  ch.duty = 0;
  ch.hpoint = 0;
  ledc_channel_config(&ch);
}

void motorInit() {
  pinMode(PIN_BTS7960_EN, OUTPUT);
  digitalWrite(PIN_BTS7960_EN, LOW);

  ledc_timer_config_t timer = {};
  timer.speed_mode = LEDC_LOW_SPEED_MODE;
  timer.duty_resolution = kLedcDutyRes;
  timer.timer_num = LEDC_TIMER_0;
  timer.freq_hz = LEDC_STEER_FREQ_HZ;
  timer.clk_cfg = LEDC_AUTO_CLK;
  ledc_timer_config(&timer);

  motorLedcAttachPin(PIN_BTS7960_RPWM, kLedcChR);
  motorLedcAttachPin(PIN_BTS7960_LPWM, kLedcChL);

  motorSteerCenter();
}

static void setPwm(ledc_channel_t ch, uint8_t pwm) {
  const uint32_t maxDuty =
      (1U << static_cast<uint32_t>(LEDC_STEER_RESOLUTION_BITS)) - 1U;
  const uint32_t duty = (static_cast<uint32_t>(pwm) * maxDuty) / 255U;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, ch, duty);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, ch);
}

void motorSteerLeft(uint8_t pwm) {
  setPwm(kLedcChR, 0);
  setPwm(kLedcChL, pwm);
}

void motorSteerRight(uint8_t pwm) {
  setPwm(kLedcChL, 0);
  setPwm(kLedcChR, pwm);
}

void motorSteerCenter() {
  setPwm(kLedcChR, 0);
  setPwm(kLedcChL, 0);
}

void motorEnable() {
  digitalWrite(PIN_BTS7960_EN, HIGH);
}

void motorDisable() {
  digitalWrite(PIN_BTS7960_EN, LOW);
  motorSteerCenter();
}
