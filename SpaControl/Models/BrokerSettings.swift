import Foundation

enum BrokerSettings {
    static let hostKey     = "broker_host"
    static let portKey     = "broker_port"
    static let usernameKey = "broker_username"
    static let passwordKey = "broker_password"

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
}
