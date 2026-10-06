// firmware/src/config.h
#pragma once

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// WiFi: try STA (home router) first; if it fails or SSID is empty, start Soft AP.
// Use different SSID/password for STA vs AP.
// ---------------------------------------------------------------------------
// Set both to join your router; leave SSID empty to use Soft AP only at boot.
static constexpr const char *WIFI_STA_SSID = "";
static constexpr const char *WIFI_STA_PASSWORD = "";
static constexpr uint32_t WIFI_STA_CONNECT_TIMEOUT_MS = 12000;
// If true, run STA-only (no robot hotspot). Phone/controller must be on same router.
static constexpr bool WIFI_FORCE_STA_MODE = false;

// Fallback hotspot (phone joins this). Must differ from STA; WPA2 password >= 8 chars.
static constexpr const char *WIFI_AP_SSID = "CartRobot_Setup";
static constexpr const char *WIFI_AP_PASSWORD = "cartsetup";
static constexpr uint8_t WIFI_AP_IP_A = 192;
static constexpr uint8_t WIFI_AP_IP_B = 168;
static constexpr uint8_t WIFI_AP_IP_C = 4;
static constexpr uint8_t WIFI_AP_IP_D = 1;
static constexpr uint8_t WIFI_AP_MASK_A = 255;
static constexpr uint8_t WIFI_AP_MASK_B = 255;
static constexpr uint8_t WIFI_AP_MASK_C = 255;
static constexpr uint8_t WIFI_AP_MASK_D = 0;

// ---------------------------------------------------------------------------
// WebSocket
// ---------------------------------------------------------------------------
static constexpr uint16_t WEBSOCKET_PORT = 8080;
static constexpr uint32_t TELEMETRY_INTERVAL_MS = 100;
static constexpr uint32_t WATCHDOG_NO_MESSAGE_MS = 8000;

// ---------------------------------------------------------------------------
// Pins — BTS7960
// ---------------------------------------------------------------------------
static constexpr int PIN_BTS7960_RPWM = 18;
static constexpr int PIN_BTS7960_LPWM = 19;
static constexpr int PIN_BTS7960_EN = 4;

// ---------------------------------------------------------------------------
// Pins — drive relays
// ---------------------------------------------------------------------------
static constexpr int PIN_RELAY_A = 16;
static constexpr int PIN_RELAY_B = 17;

// ---------------------------------------------------------------------------
// Pins — I2C LCD (if blank, try SDA=4 SCL=15 or match your working sketch)
// ---------------------------------------------------------------------------
static constexpr int PIN_I2C_SDA = 21;
static constexpr int PIN_I2C_SCL = 22;
static constexpr uint32_t LCD_I2C_HZ = 100000;
// 0 = auto-scan PCF8574 backpack; else force 7-bit addr (e.g. 0x27, 0x3F, 0x20).
static constexpr uint8_t LCD_I2C_ADDR_FORCE = 0;
static constexpr uint8_t LCD_I2C_ADDR_PRIMARY = 0x27;
static constexpr uint8_t LCD_I2C_ADDR_FALLBACK = 0x3F;

// ---------------------------------------------------------------------------
// Pins — HC-SR04 (distance: telemetry dist_cm, auto-mode obstacle avoidance, buzzer proximity)
// ---------------------------------------------------------------------------
static constexpr int PIN_ULTRASONIC_TRIG = 5;
static constexpr int PIN_ULTRASONIC_ECHO = 23;

// ---------------------------------------------------------------------------
// Pins — potentiometer (ADC1 only)
// ---------------------------------------------------------------------------
static constexpr int PIN_POT_ADC = 34;

// ---------------------------------------------------------------------------
// Pins — buttons (active-low).
// Press shorts the pin to GND. A 10k pull-up goes to 3.3V (not 5V).
// GPIO35 is input-only and has no internal pull-up, so the external resistor is required.
// ---------------------------------------------------------------------------
static constexpr int PIN_BUTTON_DRIVE_ENABLE = 33;
static constexpr int PIN_BUTTON_AUTO_MODE = 35;

// ---------------------------------------------------------------------------
// Pins — LEDs (digital outputs; not used for analogRead)
// ---------------------------------------------------------------------------
static constexpr int PIN_LED_LEFT = 25;
static constexpr int PIN_LED_RIGHT = 26;
static constexpr int PIN_LED_HEADLIGHT = 27;
// Common with NPN/ULN2003: LED turns ON when GPIO is LOW.
static constexpr bool LED_GPIO_ACTIVE_LOW = true;

// ---------------------------------------------------------------------------
// Pins — buzzer (active HIGH)
// ---------------------------------------------------------------------------
static constexpr int PIN_BUZZER = 32;

// ---------------------------------------------------------------------------
// LEDC steering
// ---------------------------------------------------------------------------
static constexpr uint32_t LEDC_STEER_FREQ_HZ = 20000;
static constexpr uint8_t LEDC_STEER_RESOLUTION_BITS = 8;

// ---------------------------------------------------------------------------
// Timings
// ---------------------------------------------------------------------------
static constexpr uint32_t ULTRASONIC_TIMER_PERIOD_MS = 60;
static constexpr uint32_t ULTRASONIC_ECHO_TIMEOUT_US = 30000;
static constexpr float ULTRASONIC_FAR_CM = 250.0f;
static constexpr uint32_t LCD_UPDATE_MIN_INTERVAL_MS = 200;
static constexpr uint32_t BUTTON_DEBOUNCE_MS = 50;

static constexpr uint32_t INDICATOR_BLINK_HALF_MS = 250;
static constexpr uint32_t RECORD_HEADLIGHT_HALF_MS = 500;

static constexpr uint32_t ROUTE_SAMPLE_MS = 100;
static constexpr size_t ROUTE_MAX_STEPS = 500;

static constexpr uint32_t AUTO_AVOID_TURN_MS = 600;
static constexpr uint32_t AUTO_AVOID_FORWARD_MS = 800;
static constexpr uint32_t AUTO_RESUME_STEER_MS = 400;

// ---------------------------------------------------------------------------
// Pot → sensitivity
// ---------------------------------------------------------------------------
static constexpr int POT_ADC_SAMPLES = 8;
static constexpr int POT_ADC_MIN = 0;
static constexpr int POT_ADC_MAX = 4095;
static constexpr float STEER_SENSITIVITY_MIN = 0.1f;
static constexpr float STEER_SENSITIVITY_MAX = 2.0f;

static constexpr uint8_t DEFAULT_COMMANDED_SPEED_PWM = 200;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
enum class DriveCmd : uint8_t { Stop = 0, Forward = 1, Reverse = 2 };
enum class SteerCmd : uint8_t { Center, Left, Right };

enum class RouteFsm : uint8_t { Idle, Recording, Playing, PlayingReverse };

enum class AutoFsm : uint8_t { Forward, AvoidTurn, AvoidForward, Resume };

enum class PendingRouteAction : uint8_t {
  None,
  RecordStart,
  RecordStop,
  Playback,
  PlaybackReverse,
  Stop,
  ClearMemory
};

struct RouteStep {
  uint8_t drive;
  int16_t steer_pwm;
  uint32_t duration_ms;
};

struct SharedRobotState {
  bool motorEnabled;
  bool autoMode;
  bool navLedsEnabled;
  bool headlightOn;
  bool buzzerMuted;
  bool watchdogTripped;

  DriveCmd driveCmd;
  SteerCmd steerCmd;
  uint8_t steerPwmRaw;
  uint8_t lastCommandedSpeedPwm;

  uint32_t lastWsMessageMs;
  int wsClientCount;
  bool wifiReady;

  PendingRouteAction pendingRoute;

  int telemetryDistCm;
  uint8_t telemetrySteerPwm;
  DriveCmd telemetryDrive;
  bool telemetryEnabled;
  bool telemetryAuto;
  bool telemetryNavLeds;
  bool telemetryHeadlight;
  bool telemetryBuzzerMuted;
  bool telemetryBtn1;
  bool telemetryBtn2;
  float telemetrySensitivity;
  RouteFsm telemetryRouteState;
  uint16_t telemetryRouteStep;
  uint16_t telemetryRouteTotal;
};

extern SharedRobotState g_state;
extern SemaphoreHandle_t g_stateMutex;

inline bool takeStateMutex(TickType_t ticks = pdMS_TO_TICKS(50)) {
  return g_stateMutex != nullptr && xSemaphoreTake(g_stateMutex, ticks) == pdTRUE;
}

inline void giveStateMutex() {
  if (g_stateMutex != nullptr) {
    xSemaphoreGive(g_stateMutex);
  }
}
