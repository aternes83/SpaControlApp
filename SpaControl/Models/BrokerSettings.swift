import Foundation

enum BrokerSettings {
    static let hostKey     = "broker_host"
    static let portKey     = "broker_port"
    static let usernameKey = "broker_username"
    static let passwordKey = "broker_password"
    static let deviceIdKey = "broker_device_id"

    static var host: String {
        UserDefaults.standard.string(forKey: hostKey) ?? ""
    }
    static var port: Int {
        let p = UserDefaults.standard.integer(forKey: portKey)
        return p > 0 ? p : 8883
    }
    static var username: String {
        UserDefaults.standard.string(forKey: usernameKey) ?? ""
    }
    static var password: String {
        UserDefaults.standard.string(forKey: passwordKey) ?? ""
    }

    /// Identifies which spa this app is paired to (from the controller over BLE).
    /// Empty = legacy single-spa topics.
    static var deviceId: String {
        UserDefaults.standard.string(forKey: deviceIdKey) ?? ""
    }

    /// MQTT topics, scoped to the paired device when a deviceId is set.
    static var statusTopic: String {
        deviceId.isEmpty ? "spa/status" : "spa/\(deviceId)/status"
    }
    static var commandTopic: String {
        deviceId.isEmpty ? "spa/commands" : "spa/\(deviceId)/commands"
    }
    /// Retained liveness, written by the controller on connect and by the broker
    /// (as the controller's last will) when it stops answering keepalives. This
    /// is the only topic that can tell a cold app the tub is off the network —
    /// `status` is retained too, so it hands over a plausible-looking snapshot
    /// of a spa that died hours ago. See docs/MQTT.md in the firmware repo.
    static var onlineTopic: String {
        deviceId.isEmpty ? "spa/online" : "spa/\(deviceId)/online"
    }

    /// Persist broker settings (e.g. fetched from the controller over BLE).
    static func save(host: String, port: Int, username: String, password: String, deviceId: String = "") {
        let d = UserDefaults.standard
        d.set(host, forKey: hostKey)
        d.set(port, forKey: portKey)
        d.set(username, forKey: usernameKey)
        d.set(password, forKey: passwordKey)
        if !deviceId.isEmpty { d.set(deviceId, forKey: deviceIdKey) }
    }
}
