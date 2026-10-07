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

- **Drive**: Forward / reverse via relays on GPIO 16 and 17.
- **Steering**: Two relays (GPIO 18 right, GPIO 4 left). Same relay state is stopped. A timed run changes the wheel angle. 0° is straight forward and 180° is straight in reverse.
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
| **Drive relays** | GPIO 16 and 17. Forward and reverse. |
| **Steering relays** | GPIO 18 right, GPIO 4 left. Rest is both off (or both on if `STEER_REST_BOTH_ON`). |
| **HC‑SR04** | Trigger + echo pins; timing limits and “far” distance in config. |
| **Potentiometer (ADC)** | Limits how far the stick may steer, as a fraction of a half-turn. |
| **Buttons** | Drive enable, auto mode (with debounce). |
| **LEDs** | Left/right nav, headlight — **often wired active-low** (LED on when GPIO is **LOW**). See `LED_GPIO_ACTIVE_LOW`. |
| **Buzzer** | Digital output (active high in config). |
| **I2C LCD** | PCF8574 backpack; address scan or forced address in config. |

> **Important:** Always align `config.h` with your actual PCB/wiring. Wrong pins or active-low vs active-high assumptions will cause inverted LEDs or dangerous motion.

## Steering calibration

Turn the motors on, then open **Settings → Steering calibration**.

1. Hold **Jog left** or **Jog right** until the wheel points straight forward. Press **Set centre**. That position is 0°. 180° is the same line, with the wheel turned around for reverse.
2. Press **Start right-end timing** and stop it when the wheel reaches the right end (reverse-straight is 180°). That sets degrees per second on the right relay.
3. Press **Start left-end timing** and stop it at the left end (through 270°). That sets the left rate.
4. Press **Save to robot**. The values stay in flash.

**Recentre** drives to one end, then back to 0° for the saved travel time. **Reset defaults** restores `config.h`. A direction change always pauses in the rest state for the dead time before the relays swap.

---

## Networking: access point vs home Wi‑Fi

The robot supports both **Soft AP (Hotspot)** mode and **Station (Shared Wi‑Fi)** mode with runtime provisioning saved in non-volatile flash memory (NVS via ESP32 `Preferences`):

### 1. Default Hotspot Mode (`CartRobot_Setup`)
- On first boot (or after a reset), the robot broadcasts an access point: **`CartRobot_Setup`** (password `12345678`, or as set in `config.h`).
- The robot is reachable at **`192.168.4.1:8080`**.
- Connect your phone to this Wi-Fi network and open the app. The app connects to `192.168.4.1`.

### 2. Switching to Shared Wi‑Fi (In-App Provisioning)
- Tap the **Wi‑Fi status chip / button** in the app (available on the Connection screen, Controller top bar, or Settings menu) to open **Wi‑Fi Setup**.
- Tap **Scan Networks** to list available 2.4 GHz Wi‑Fi networks with signal strength bars.
- Select your Wi‑Fi network, enter the password, and tap **Connect Robot to Wi‑Fi**.
- The robot connects to your shared Wi‑Fi router while maintaining client communication, saves credentials into NVS, and obtains an IP via DHCP.
- When connected, the app offers a one-tap **"Switch App to New IP & Reconnect"** button that automatically repoints the dashboard to the robot's new LAN IP.

### 3. LCD Display of IP Address
- When the robot successfully joins the shared Wi‑Fi, the I2C LCD immediately displays a 10-second banner:
  ```
  NEW IP (WIFI):
  192.168.x.y
  ```
- In normal operating mode, Line 2 of the 16x2 LCD rotates every 3 seconds between sensor distance (`DIST: 45cm`) and the active network IP (`STA 192.168.x.y` or `AP 192.168.4.1`), ensuring the operator can always check the IP directly on the robot hardware without opening a router admin console.

### 4. Hardware Button Reset to Hotspot Mode (Recovery)
If the shared Wi‑Fi is unavailable or the credentials change, you can instantly revert the robot back to Hotspot mode without a computer:
- **ESP32 On-board BOOT Button (GPIO 0)**: Press and hold the **BOOT button** on the ESP32 DevKit board for **>= 800ms**. The buzzer will beep and the LCD will display `HOTSPOT RESET`. Stored Wi-Fi credentials in NVS are cleared and the robot immediately boots standalone Hotspot (`CartRobot_Setup` at `192.168.4.1`, password `cartsetup`).
- **Button 1 (GPIO 33)**: Press and hold **Button 1** (`PIN_BUTTON_DRIVE_ENABLE`) for **>= 1.8 seconds**. Beeps and resets to Hotspot. *(Short tap continues to toggle motor drive enable instantly).*
- **Button 2 (GPIO 35)**: If wired, press and hold for 3 seconds to open the Onboard Setup Menu on the LCD (`1.RESET HOTSPOT`). Short tap toggles Auto Mode.
- **In-App Reset**: Tapping "Reset Robot to Hotspot" in the Wi-Fi Setup sheet sends `wifi_reset`.

---

## Communication protocol

All commands are **JSON objects** with at least `"cmd": "<name>"`.

| Command | Purpose |
|---------|---------|
| `ping` | Keepalive; server replies with `pong` (used for latency). |
| `move` | `dir`: `fwd`, `rev`, `stop` |
| `steer_angle` | `angle`: degrees. 0 and 180 are straight. Right increases the angle. |
| `straight` | Hold the nearer of 0° or 180°. |
| `recentre` | Drive to a stop, then back to 0°. |
| `steer` | Old form. `dir` + `pwm` is converted to an angle. |
| `get_calib` / `set_calib` / `calib_save` | Read, change, or store steering calibration. |
| `calib_jog` | `dir`: `left` or `right`, `duration_ms`. `0` stops. |
| `calib_measure_start` / `calib_measure_stop` | Time a run. Stop takes optional `span_deg`. |
| `calib_set_centre` / `calib_reset_defaults` | Mark the current wheel as 0°, or restore defaults. |
| `enable` | `state`: bool — motor enable |
| `auto` | `state`: bool — auto mode |
| `leds` | `nav`: bool — nav LEDs; optional `headlight`: bool |
| `buzzer` | `mute`: bool |
| `route` | `action`: `record_start`, `record_stop`, `playback`, `playback_reverse`, `stop`, `clear` |
| `wifi_scan` | Requests an async scan of 2.4 GHz networks; server replies with `wifi_scan_results`. |
| `wifi_connect` | `ssid`: string, `pass`: string — connects ESP32 to shared Wi-Fi and persists in NVS. |
| `wifi_reset` | Clears stored Wi-Fi credentials and switches back to SoftAP mode (`192.168.4.1`). |

Telemetry is sent as JSON periodically (fields include `dist_cm`, `steer_angle`, `steer_dir`, `sensitivity`, `drive_cmd`, `drive_enabled`, `auto_mode`, `nav_leds`, route step/total, `wifi_mode` ["ap"/"sta"], `wifi_ssid`, and `ip`).

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
