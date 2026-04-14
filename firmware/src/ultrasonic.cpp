// firmware/src/ultrasonic.cpp
#include "ultrasonic.h"
#include "config.h"

#include <driver/gpio.h>
#include <esp32-hal-timer.h>
#include <esp_timer.h>
#include <rom/ets_sys.h>

static volatile uint32_t s_echoWidthUs = 0;
static volatile bool s_echoFresh = false;
static portMUX_TYPE s_echoMux = portMUX_INITIALIZER_UNLOCKED;

static uint32_t IRAM_ATTR timeUs_isr() {
  return static_cast<uint32_t>(esp_timer_get_time());
}

static void IRAM_ATTR ultrasonic_echo_isr(void *) {
  static uint32_t riseUs = 0;
  if (gpio_get_level(static_cast<gpio_num_t>(PIN_ULTRASONIC_ECHO)) == 1) {
    riseUs = timeUs_isr();
  } else {
    const uint32_t now = timeUs_isr();
    const uint32_t width = now - riseUs;
    portENTER_CRITICAL_ISR(&s_echoMux);
    if (width > 0 && width <= ULTRASONIC_ECHO_TIMEOUT_US) {
      s_echoWidthUs = width;
      s_echoFresh = true;
    }
    portEXIT_CRITICAL_ISR(&s_echoMux);
  }
}

static hw_timer_t *s_trigTimer = nullptr;

void IRAM_ATTR ultrasonic_timer_isr() {
  digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
  ets_delay_us(10);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
}

void ultrasonicInit() {
  pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  pinMode(PIN_ULTRASONIC_ECHO, INPUT);
  attachInterruptArg(digitalPinToInterrupt(PIN_ULTRASONIC_ECHO), ultrasonic_echo_isr, nullptr,
                     CHANGE);

#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
  s_trigTimer = timerBegin(1000000);
  if (s_trigTimer) {
    timerAttachInterrupt(s_trigTimer, &ultrasonic_timer_isr, true);
    timerAlarm(s_trigTimer, ULTRASONIC_TIMER_PERIOD_MS * 1000, true, 0);
  }
#else
  s_trigTimer = timerBegin(0, 80, true);
  if (s_trigTimer) {
    timerAttachInterrupt(s_trigTimer, &ultrasonic_timer_isr, true);
    timerAlarmWrite(s_trigTimer, ULTRASONIC_TIMER_PERIOD_MS * 1000, true);
    timerAlarmEnable(s_trigTimer);
  }
#endif
}

float ultrasonicGetDistanceCm() {
  uint32_t width = 0;
  bool fresh = false;
  portENTER_CRITICAL(&s_echoMux);
  if (s_echoFresh) {
    width = s_echoWidthUs;
    fresh = true;
    s_echoFresh = false;
  }
  portEXIT_CRITICAL(&s_echoMux);

  if (!fresh || width == 0) {
    return ULTRASONIC_FAR_CM;
  }
  return static_cast<float>(width) / 58.0f;
}
