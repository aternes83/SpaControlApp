# SpaControl iOS App

Native SwiftUI app for controlling the ESP32-S3 spa controller via MQTT (HiveMQ Cloud).

## Build & Run

The Xcode project is committed and ready to open — no manual project creation needed.

### 1. Open the project
```bash
open SpaControl.xcodeproj
```
On first open, Xcode automatically resolves the **CocoaMQTT** Swift Package
(`https://github.com/emqx/CocoaMQTT`, up to next major from `2.1.0`).

### 2. Set your signing team
- Select the **SpaControl** target → **Signing & Capabilities**
- Choose your Team (bundle id defaults to `com.spacontrol.SpaControl`; change if needed)

### 3. Run
Build and run on a device or simulator (**iOS 16+**).

### Regenerating the project (optional)
`SpaControl.xcodeproj` is generated from [`project.yml`](project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source
of truth. After changing project structure (targets, packages, settings),
regenerate with:
```bash
xcodegen generate
```
Adding/removing Swift files under `SpaControl/` needs no regeneration — the
target globs the folder, so new files are picked up automatically.

---

## First Launch

The Settings sheet opens automatically. Enter your HiveMQ Cloud credentials:

| Field    | Example value |
|----------|---------------|
| Host     | `xxxx.s1.eu.hivemq.cloud` |
| Port     | `8883` |
| Username | your HiveMQ username |
| Password | your HiveMQ password |

Tap **Connect**. The status dot turns green and the dashboard populates within 30 s
(when the next `spa/status` publish arrives from the board).

---

## MQTT Topics

| Topic | Direction | Format |
|-------|-----------|--------|
| `spa/status` | Board → App | `{"temp_f":95.0,"setpoint":104.0,"heater":false,"pump1":1,"pump2":false,"pump3":false,"light":true,"eco":false,"fault":false,"fault_code":0}` |
| `spa/commands` | App → Board | Any subset of `{"set_temp":104,"pump1":2,"pump2":true,"pump3":true,"light":true,"eco":false,"max_jet":true}` |

## File Structure

```
SpaControl/
├── SpaControlApp.swift          # @main entry point
├── Models/
│   ├── SpaStatus.swift          # Decodable — incoming broker payload
│   ├── SpaCommand.swift         # Encodable — outgoing control payload
│   └── BrokerSettings.swift     # UserDefaults key constants + accessors
├── ViewModels/
│   └── SpaViewModel.swift       # ObservableObject: MQTT client, @Published state
└── Views/
    ├── ContentView.swift         # Root nav + sheet presentation
    ├── StatusDashboardView.swift # Scroll layout + fault banner
    ├── TemperatureControlView.swift  # Current temp + setpoint ±1 buttons
    ├── PumpControlView.swift     # Pump 1 segmented + Pump 2/3 tap cards
    ├── LightEcoControlView.swift # Light, Eco, Max Jets cards
    ├── ConnectionStatusView.swift # Connected/Connecting/Disconnected capsule
    └── SettingsSheet.swift       # @AppStorage form + Connect button
```
