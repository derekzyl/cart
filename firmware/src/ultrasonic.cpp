// firmware/src/ultrasonic.cpp
#include "ultrasonic.h"
#include "config.h"

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

static float s_lastCm = ULTRASONIC_FAR_CM;
static uint32_t s_lastEchoMs = 0;
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;

static void ultrasonicTask(void *param) {
  (void)param;

  vTaskDelay(pdMS_TO_TICKS(300));

  uint32_t lastLogMs = 0;

  for (;;) {
    const uint32_t now = millis();

    // 1. Ensure pins are set
    pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
    digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
    pinMode(PIN_ULTRASONIC_ECHO, INPUT_PULLDOWN);
    delayMicroseconds(4);

    // 2. Check if ECHO pin is already HIGH before trigger
    const bool echoPreHigh = (digitalRead(PIN_ULTRASONIC_ECHO) == HIGH);

    // 3. Emit 10us trigger pulse
    digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
    delayMicroseconds(10);
    digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

    // 4. Wait for ECHO to rise HIGH (timeout 10ms = 10,000us)
    const uint32_t tStart = micros();
    bool echoRose = false;
    while ((micros() - tStart) < 10000UL) {
      if (digitalRead(PIN_ULTRASONIC_ECHO) == HIGH) {
        echoRose = true;
        break;
      }
    }

    uint32_t echoWidthUs = 0;
    if (echoRose) {
      const uint32_t tHigh = micros();
      while ((micros() - tHigh) < 30000UL) {
        if (digitalRead(PIN_ULTRASONIC_ECHO) == LOW) {
          echoWidthUs = micros() - tHigh;
          break;
        }
      }
      // If it stayed high for full 30ms without dropping, target is beyond max range
      if (echoWidthUs == 0) {
        echoWidthUs = 30000UL;
      }
    }

    portENTER_CRITICAL(&s_mux);
    if (echoRose && echoWidthUs > 0) {
      float cm = static_cast<float>(echoWidthUs) / 58.2f;
      if (cm > 400.0f) {
        cm = ULTRASONIC_FAR_CM; // open space / far target
      }
      if (cm < 2.0f) {
        cm = 2.0f;
      }

      if (s_lastEchoMs == 0) {
        s_lastCm = cm;
      } else {
        // Smooth out noise (75% new, 25% previous)
        s_lastCm = (cm * 0.75f) + (s_lastCm * 0.25f);
      }
      s_lastEchoMs = now;
    } else {
      // Echo never rose
      if (now - s_lastEchoMs > 1500) {
        s_lastCm = -1.0f;
      }
    }
    portEXIT_CRITICAL(&s_mux);

    // Serial debug print every 1.5 seconds
    if (now - lastLogMs >= 1500) {
      lastLogMs = now;
      if (echoRose) {
        Serial.printf("[US] echo=%lu us -> %.1f cm\n", (unsigned long)echoWidthUs, s_lastCm);
      } else if (echoPreHigh) {
        Serial.println("[US-WARN] ECHO pin stuck HIGH before trigger (check wiring/divider)");
      } else {
        Serial.printf("[US-WARN] ECHO pin stayed LOW (Trig=GPIO%d, Echo=GPIO%d)\n",
                      PIN_ULTRASONIC_TRIG, PIN_ULTRASONIC_ECHO);
      }
    }

    // Measurement cycle: 70ms = ~14Hz
    vTaskDelay(pdMS_TO_TICKS(70));
  }
}

void ultrasonicInit() {
  pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
  pinMode(PIN_ULTRASONIC_ECHO, INPUT_PULLDOWN);

  // Background task on Core 1 with priority 2
  xTaskCreatePinnedToCore(ultrasonicTask, "ultrasonic", 3072, nullptr, 2, nullptr, 1);
}

float ultrasonicGetDistanceCm() {
  portENTER_CRITICAL(&s_mux);
  const float val = s_lastCm;
  portEXIT_CRITICAL(&s_mux);
  return val;
}

uint32_t ultrasonicEchoAgeMs() {
  portENTER_CRITICAL(&s_mux);
  const uint32_t last = s_lastEchoMs;
  portEXIT_CRITICAL(&s_mux);
  if (last == 0) {
    return 0xFFFFFFFFUL;
  }
  return millis() - last;
}
