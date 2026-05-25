# SpaControl iOS App

Native SwiftUI app for controlling the ESP32-S3 spa controller via MQTT (HiveMQ Cloud).

## Xcode Setup (one-time)

### 1. Create the Xcode project
- File → New → Project → iOS → App
- Product Name: `SpaControl`
- Bundle Identifier: `com.yourname.SpaControl`
- Interface: **SwiftUI**, Language: **Swift**
- Minimum Deployments: **iOS 16**
- Uncheck "Include Tests" for now

### 2. Add CocoaMQTT via Swift Package Manager
- File → Add Package Dependencies…
- URL: `https://github.com/emqx/CocoaMQTT`
- Dependency Rule: Up to Next Major Version from `2.1.0`
- Add **CocoaMQTT** to the `SpaControl` target

### 3. Replace the generated files with this repo's files
- Delete `ContentView.swift` and `<AppName>App.swift` that Xcode generated
- Drag the folders `Models/`, `ViewModels/`, `Views/`, and `SpaControlApp.swift`
  from this directory into the Xcode project navigator
- Make sure "Copy items if needed" is **unchecked** (or checked if you want a copy)
- Target membership: `SpaControl` ✓

### 4. Run
Build and run on a device or simulator (iOS 16+).

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
