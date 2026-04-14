# Cart — ESP32 robot wireless controller

This repository contains a complete **embedded control stack** for a small electric cart or similar vehicle: **firmware** that runs on an **ESP32** (motors, relays, steering PWM, sensors, Wi‑Fi/WebSocket server) and a **Flutter** **Android** app that acts as a wireless dashboard and remote control.

The phone connects over **Wi‑Fi** using **JSON messages over WebSockets**. Telemetry (distance, steering, route playback, buttons, etc.) is pushed from the robot to the app in real time.

---

## Table of contents

1. [High-level architecture](#high-level-architecture)
2. [Features](#features)
3. [Hardware expectations](#hardware-expectations)
4. [Networking: access point vs home Wi‑Fi](#networking-access-point-vs-home-wi-fi)
5. [Communication protocol](#communication-protocol)
6. [Route memory](#route-memory)
7. [Ultrasonic sensor](#ultrasonic-sensor)
8. [Repository layout](#repository-layout)
9. [Build: firmware (ESP32)](#build-firmware-esp32)
10. [Build: Flutter app](#build-flutter-app)
11. [Configuration reference](#configuration-reference)
12. [Troubleshooting](#troubleshooting)
13. [Safety](#safety)

---

## High-level architecture

```
┌─────────────────────┐     Wi‑Fi (LAN or robot AP)      ┌──────────────────────┐
│  Android phone      │  ◄──── WebSocket JSON ───────►  │  ESP32               │
│  Flutter app        │       Telemetry + commands       │  Arduino framework   │
│  (app/)             │       HTTP /health (probe)     │  (firmware/)       │
└─────────────────────┘                                    └──────────┬─────────┘
                                                                      │
                                                          Motors, relays, PWM,
                                                          LCD, LEDs, buzzer,
                                                          ultrasonic, buttons
```

- **Firmware** (`firmware/`): FreeRTOS-friendly loop, motor/relay control, optional I2C LCD, HC‑SR04 ranging, LEDC steering, route recording/playback, auto obstacle-avoidance mode, Async WebSocket server on a configurable TCP port (default **8080**).
- **App** (`app/`): Landscape UI, connection screen, joystick + FWD/REV, speed/sensitivity, telemetry panel, route controls, LED/buzzer toggles, settings (IP/port), automatic reconnect with backoff when the network returns.

---

## Features

### On the robot (firmware)

- **Drive**: Forward / reverse via relays; steering via **PWM** (BTS7960-style H-bridge or similar wiring as implemented in `motor.cpp` / `relay.cpp`).
- **Enable & auto**: Physical buttons can toggle motor enable and **auto mode** (obstacle-related behavior uses ultrasonic distance).
- **WebSocket API**: JSON commands for move, steer, enable, auto, LEDs, buzzer, route actions, ping/pong.
- **Watchdog**: If commands stop arriving for a configured interval, the robot can trip a safety state (see `WATCHDOG_NO_MESSAGE_MS` in `config.h`).
- **Route memory**: Record a timed sequence of drive + steer steps, play it forward or in reverse, stop, or **clear** stored memory.
- **Telemetry**: Periodic JSON broadcast with distance, PWM, drive state, flags, route progress, etc.
- **Optional display**: I2C LCD for status (recording/playback, distance, etc.).

### In the app

- **Connection**: Default host `192.168.4.1`, port `8080` (robot access-point mode). Configurable in settings.
- **Control**: Virtual joystick, dedicated FWD/REV, steering arc, enable/auto toggles, speed/command rate.
- **Route UI**: Record, stop, play, return (reverse playback), **clear memory**, progress display.
- **Resilience**: Reconnect with exponential backoff; optional connectivity listener to retry when Wi‑Fi comes back; subnet hint when targeting the robot AP without a `192.168.4.x` address.

---

## Hardware expectations

Pin assignments are centralized in **`firmware/src/config.h`**. Typical groups:

| Subsystem | Notes |
|-----------|--------|
| **BTS7960 / motor driver** | RPWM, LPWM, EN pins as defined in config. |
| **Relays** | Often used for high-level FWD/REV or contactor-style switching. |
| **Steering** | LEDC PWM at configured frequency/resolution. |
| **HC‑SR04** | Trigger + echo pins; timing limits and “far” distance in config. |
| **Potentiometer (ADC)** | Maps to **steer sensitivity** range. |
| **Buttons** | Drive enable, auto mode (with debounce). |
| **LEDs** | Left/right nav, headlight — **often wired active-low** (LED on when GPIO is **LOW**). See `LED_GPIO_ACTIVE_LOW`. |
| **Buzzer** | Digital output (active high in config). |
| **I2C LCD** | PCF8574 backpack; address scan or forced address in config. |

> **Important:** Always align `config.h` with your actual PCB/wiring. Wrong pins or active-low vs active-high assumptions will cause inverted LEDs or dangerous motion.

---

## Networking: access point vs home Wi‑Fi

Configured in **`firmware/src/config.h`**:

- **Soft AP (hotspot)**  
  - Default SSID/password are defined (`WIFI_AP_SSID`, `WIFI_AP_PASSWORD`).  
  - Robot is usually at **`192.168.4.1`** (classic ESP32 AP addressing).  
  - The phone joins this network and points the app at `192.168.4.1:8080`.

- **Station mode (STA)**  
  - Set `WIFI_STA_SSID` / `WIFI_STA_PASSWORD` to join your router.  
  - Use `WIFI_FORCE_STA_MODE` if you want STA-only behavior.  
  - The app must use the **robot’s DHCP address** on your LAN (check router admin or serial logs), not `192.168.4.1`.

The Flutter service probes **`http://<host>:<port>/health`** and **`ws://<host>:<port>/ws`** (with fallbacks) to establish a session.

---

## Communication protocol

All commands are **JSON objects** with at least `"cmd": "<name>"`.

| Command | Purpose |
|---------|---------|
| `ping` | Keepalive; server replies with `pong` (used for latency). |
| `move` | `dir`: `fwd`, `rev`, `stop` |
| `steer` | `dir`: `left`, `right`, `center`; `pwm`: 0–255 |
| `enable` | `state`: bool — motor enable |
| `auto` | `state`: bool — auto mode |
| `leds` | `nav`: bool — nav LEDs; optional `headlight`: bool |
| `buzzer` | `mute`: bool |
| `route` | `action`: `record_start`, `record_stop`, `playback`, `playback_reverse`, `stop`, `clear` |

Telemetry is sent as JSON (fields such as distance, steering PWM, drive command, enabled/auto flags, `nav_leds`, route step/total, etc.—see `webserver.cpp` and `telemetry_model.dart` in the app).

---

## Route memory

- **Recording** samples drive + steer at **`ROUTE_SAMPLE_MS`** intervals, up to **`ROUTE_MAX_STEPS`** steps.
- **Playback** replays the sequence; **playback_reverse** runs it backward.
- **Stop** halts playback/recording as applicable.
- **Clear** (`action`: `clear`) wipes stored route data when processed on the main loop (pending action pattern avoids races with the WebSocket task).

The app exposes **Clear memory** when the route is idle and a non-zero route exists (`total > 0`).

---

## Ultrasonic sensor

The **HC‑SR04** provides **distance in centimeters** for:

- **Telemetry** (`dist_cm` / equivalent fields) so the phone can show obstacle distance.
- **Auto mode** logic (turn / forward / resume timers — see `auto_mode.cpp` and constants like `AUTO_AVOID_*`).
- **Buzzer** proximity feedback (when not muted).

If distance reads as invalid or wiring is wrong, auto behavior and buzzer hints will not match expectations—verify trigger/echo pins and 5 V / logic levels.

---

## Repository layout

```
cart/
├── README.md                 ← this file
├── firmware/                 ← PlatformIO ESP32 project
│   ├── platformio.ini
│   └── src/
│       ├── main.cpp          ← main loop, integration
│       ├── config.h          ← pins, Wi‑Fi, timings, types
│       ├── webserver.cpp     ← HTTP + WebSocket
│       ├── motor.cpp / relay.cpp / leds.cpp / …
│       └── …
└── app/                      ← Flutter project
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── app.dart
        ├── core/             ← WebSocket, commands, models
        ├── providers/        ← Riverpod state
        ├── screens/
        └── widgets/
```

---

## Build: firmware (ESP32)

**Prerequisites**

- [PlatformIO](https://platformio.org/) (CLI `pio` or IDE extension)
- USB cable and drivers for your ESP32 board

**Steps**

```bash
cd firmware
pio run
pio run -t upload    # when board is connected; adjust upload_port if needed
pio device monitor   # serial log at 115200 baud
```

Libraries are declared in `platformio.ini` (ESPAsyncWebServer, AsyncTCP, ArduinoJson, LiquidCrystal_I2C, etc.).

---

## Build: Flutter app

**Prerequisites**

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable), Android SDK / device or emulator

**Steps**

```bash
cd app
flutter pub get
flutter analyze
flutter run
```

The app is locked to **landscape** orientation in `main.dart`. Release builds:

```bash
flutter build apk
# or
flutter build appbundle
```

---

## Configuration reference

### Firmware (`firmware/src/config.h`)

- **Wi‑Fi**: STA vs AP, SSIDs, passwords, `WIFI_FORCE_STA_MODE`, AP IP octets.
- **Port**: `WEBSOCKET_PORT` (default **8080**).
- **Timing**: telemetry interval, watchdog timeout, ultrasonic period, route sample period, auto-mode timings.
- **Pins**: motors, relays, I2C, ultrasonic, ADC pot, buttons, LEDs, buzzer.
- **LED polarity**: `LED_GPIO_ACTIVE_LOW`.

### App (`app/lib/providers/settings_provider.dart` and in-app settings UI)

- Robot **IP** and **TCP port**
- Command rate, dead zone, sensitivity override (where exposed)

---

## Troubleshooting

| Symptom | What to check |
|--------|----------------|
| **`Network is unreachable` / errno 101** | Phone has no route to the robot (Wi‑Fi off, wrong SSID, or not yet connected). Join **CartRobot_Setup** (or your STA LAN), wait for DHCP, then reopen the app or pull to refresh connection. |
| **Cannot reach `192.168.4.1`** | You are not on the robot AP subnet. Confirm phone Wi‑Fi shows connected and IP is **`192.168.4.x`**. If using STA mode, use the robot’s **LAN** IP from serial or router. |
| **WebSocket connects then drops** | Range, power, `WATCHDOG_NO_MESSAGE_MS` too aggressive, or main loop blocked. Check serial log. |
| **LEDs inverted** | Set `LED_GPIO_ACTIVE_LOW` to match hardware (common-cathode + NPN/ULN often means ON = LOW). |
| **Joystick “stops” drive** | App avoids spamming `move: stop` while centered so FWD/REV hold works; use latest app behavior. |
| **Nav LEDs snap back in UI** | UI follows **telemetry**; do not expect a forced default on every reconnect. |

---

## Safety

This software controls **real motors**. Use fuses, proper wiring, emergency stop, and test at low speed. The authors are not responsible for injury or damage. Verify behavior on a stand before driving.

---

## License

Add a `LICENSE` file if you distribute this project; default copyright applies until you specify otherwise.
