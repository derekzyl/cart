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
// Pins — drive relays (do not retune; forward/reverse already works)
// ---------------------------------------------------------------------------
static constexpr int PIN_RELAY_A = 16;
static constexpr int PIN_RELAY_B = 17;

// ---------------------------------------------------------------------------
// Pins — steering relays. Same-state (both on or both off) is 0 V, rest.
// Different state runs the motor. GPIO 4 is this relay, not an I2C pin.
// ---------------------------------------------------------------------------
static constexpr int PIN_STEER_RELAY_RIGHT = 18;
static constexpr int PIN_STEER_RELAY_LEFT = 4;
// false: rest is both relays de-energized. true: rest is both energized.
static constexpr bool STEER_REST_BOTH_ON = false;
// true: a relay module that turns on when the GPIO is low.
static constexpr bool RELAY_ACTIVE_LOW = false;

// Commands are signed degrees from center: negative left, positive right.
// The wheel only swings ±30°. Pulses stay short so a bad estimate cannot
// run from the left stop through center and into the right stop.
static constexpr float STEER_RIGHT_DEG_PER_SEC = 200.0f;
static constexpr float STEER_LEFT_DEG_PER_SEC = 200.0f;
// Stop to stop. Each side is half of this. Kept short on purpose.
static constexpr uint32_t STEER_FULL_TRAVEL_MS = 240;
// The wheel only swings from 330° (left) through 0° to 30° (right).
static constexpr float STEER_MIN_ANGLE_DEG = 330.0f;
static constexpr float STEER_MAX_ANGLE_DEG = 30.0f;
static constexpr float STEER_CENTRE_TRIM_DEG = 0.0f;
static constexpr uint32_t STEER_DEADTIME_MS = 40;
static constexpr float STEER_STRAIGHT_DEADBAND_DEG = 3.0f;
// Wheel degrees. A smaller stick shift does not energize the L-R relays.
static constexpr float STEER_MIN_MOVE_DEG = 8.0f;

// ---------------------------------------------------------------------------
// Pins — I2C LCD (SDA 21 / SCL 22. GPIO 4 is the left steering relay.)
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
// GPIO33 rests near 0.5V: the internal pull-up (~45k) is fighting a 10k to GND,
// so digitalRead always sees LOW. A press shorts it to about 0V.
// Read the ADC and treat ~0.5V as released, ~0V as pressed.
static constexpr int PIN33_ADC_PRESSED_MAX = 350;    // about 0.28V
static constexpr int PIN33_ADC_RELEASED_MIN = 550;   // about 0.44V

inline bool buttonDriveIsPressed() {
  static bool pressed = false;
  const int adc = analogRead(PIN_BUTTON_DRIVE_ENABLE);
  if (adc <= PIN33_ADC_PRESSED_MAX) {
    pressed = true;
  } else if (adc >= PIN33_ADC_RELEASED_MIN) {
    pressed = false;
  }
  return pressed;
}
// Onboard ESP32 DevKit BOOT button (GPIO 0, active LOW with internal pull-up)
static constexpr int PIN_BUTTON_BOOT = 0;

// ---------------------------------------------------------------------------
// Pins — LEDs (digital outputs; not used for analogRead)
// ---------------------------------------------------------------------------
static constexpr int PIN_LED_LEFT = 25;
static constexpr int PIN_LED_RIGHT = 26;
static constexpr int PIN_LED_HEADLIGHT = 27;
// Active-LOW hardware: LED cathode or driver triggers on LOW, rests OFF on HIGH.
static constexpr bool LED_GPIO_ACTIVE_LOW = true;

// ---------------------------------------------------------------------------
// Pins — buzzer (active HIGH)
// ---------------------------------------------------------------------------
static constexpr int PIN_BUZZER = 32;

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
// Pot → maximum steering reach (fraction of the 180° half-turn the stick may command)
// ---------------------------------------------------------------------------
static constexpr int POT_ADC_SAMPLES = 8;
static constexpr int POT_ADC_MIN = 0;
static constexpr int POT_ADC_MAX = 4095;
static constexpr float STEER_POT_MIN = 0.15f;
static constexpr float STEER_POT_MAX = 1.0f;

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
  ClearMemory,
  DeleteNamed
};

struct RouteStep {
  uint8_t drive;
  int16_t steer_deg_x10;
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
  uint8_t lastCommandedSpeedPwm;

  uint32_t lastWsMessageMs;
  int wsClientCount;
  bool wifiReady;

  PendingRouteAction pendingRoute;
  char pendingRouteName[13];

  int telemetryDistCm;
  float telemetrySteerAngle;
  SteerCmd telemetrySteer;
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
