import Foundation
import UIKit

/// Client half of the push pipeline. Holds the APNs device token, registers it
/// (plus the user's per-category preferences) with the push service, and reports
/// whether push is the active delivery path.
///
/// When a push-service URL is configured, the **server** does detection and
/// sends notifications, so the app suppresses its own local posts (see
/// SpaViewModel). With no URL configured, the app falls back to local,
/// foreground-only alerts.
final class PushManager: ObservableObject {
    static let shared = PushManager()
    private init() {}

    // Config (UserDefaults-backed)
    static let urlKey = "push.serviceURL"
    static let tokenKey = "push.apiToken"

    @Published private(set) var deviceToken: String?
    @Published private(set) var lastRegistration: String?   // human-readable status

    var serviceURL: String { UserDefaults.standard.string(forKey: Self.urlKey) ?? "" }
    var apiToken: String { UserDefaults.standard.string(forKey: Self.tokenKey) ?? "" }

    /// True when a push service is configured — the app then defers alerting to
    /// the server and stops posting the server-covered categories locally.
    var isActive: Bool { !serviceURL.isEmpty }

    /// Ask iOS for the APNs token (safe to call once notification auth is granted).
    func registerForRemoteNotifications() {
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Called by the app delegate when APNs returns the token.
    func setDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        register()
    }

    func setRegistrationError(_ error: Error) {
        lastRegistration = "APNs registration failed: \(error.localizedDescription)"
    }

    /// Current per-category preferences as a JSON-ready dictionary.
    private var prefsPayload: [String: Bool] {
        var out: [String: Bool] = [:]
        for c in NotificationCategory.allCases { out[c.rawValue] = NotificationSettings.isEnabled(c) }
        return out
    }

    /// Register (or update) this device with the push service. No-op if push
    /// isn't configured or the token isn't available yet.
    func register() {
        // With push active, the local 30-min offline alarm is the server's job.
        if isActive { NotificationManager.shared.cancelOffline() }
        guard isActive, let token = deviceToken,
              let url = URL(string: serviceURL.appending("/register")) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty { req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["token": token, "platform": "ios", "prefs": prefsPayload]
        if !BrokerSettings.deviceId.isEmpty { body["device"] = BrokerSettings.deviceId }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.lastRegistration = "Registration failed: \(err.localizedDescription)"
                } else if let code = (resp as? HTTPURLResponse)?.statusCode {
                    self?.lastRegistration = code == 200 ? "Registered for push" : "Registration rejected (HTTP \(code))"
                }
            }
        }.resume()
    }

    /// Remove this device from the push service (call when the URL is cleared).
    func unregister(from serviceURL: String) {
        guard let token = deviceToken,
              let url = URL(string: serviceURL.appending("/unregister")) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty { req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        URLSession.shared.dataTask(with: req).resume()
    }
}
