import Foundation

/// A WiFi network reported by the ESP32's BLE scan (`{"net":{"s","r","sec"}}`).
struct WiFiNetwork: Identifiable, Hashable {
    let ssid: String
    let rssi: Int
    let secured: Bool

    var id: String { ssid }

    /// Signal strength as 1–3 bars.
    var bars: Int {
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }
}
