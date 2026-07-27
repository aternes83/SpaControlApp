import Foundation
import UserNotifications

/// Local-notification helper. Posts alerts for spa conditions (faults, freeze,
/// temperature milestones, offline, updates) and presents them even while the
/// app is foregrounded. Every post is gated by the user's per-category
/// preference in `NotificationSettings`.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    private var center: UNUserNotificationCenter { .current() }

    /// Fixed id so a rescheduled offline alarm replaces the previous one.
    private let offlineID = "spa-offline"

    /// Register as delegate so foreground notifications still present as banners.
    func configure() { center.delegate = self }

    /// Ask for alert/sound permission. Safe to call repeatedly. On grant, also
    /// registers for remote (APNs) notifications so a device token is available
    /// if/when a push service is configured.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted { PushManager.shared.registerForRemoteNotifications() }
        }
    }

    // MARK: Condition alerts

    func postReachedTarget(temp: Int) {
        fire(.reachedTarget, "✅ Target Temperature Reached",
             "The spa is now at \(temp)°F.")
    }

    func postFreeze() {
        fire(.freeze, "❄️ Freeze Protection Active",
             "Freezing conditions detected — the spa is heating to protect against freeze damage.")
    }

    func postFault(code: Int) {
        fire(.fault, "⚠️ Spa Fault — \(FaultCode.shortLabel(code))",
             FaultCode.description(code))
    }

    func postHighTemp(code: Int) {
        fire(.highTemp, "🌡️ High-Temperature Alarm",
             FaultCode.description(code) + " The heater has been shut off.")
    }

    func postSensorFault(temp: Int) {
        fire(.sensorFault, "🛑 Water-Sensor Fault",
             "The water-temperature reading (\(temp)°F) is out of range. Heating is disabled until it's resolved.")
    }

    func postLowTemp() {
        fire(.lowTemp, "🥶 Low-Temperature Alarm",
             "The spa has been heating for over 30 minutes without raising the water temperature. Check the heater or cover.")
    }

    func postFaultCleared() {
        fire(.fault, "✅ Spa Fault Cleared",
             "The spa is operating normally again.")
    }

    func postUpdateAvailable(title: String, body: String) {
        fire(.updateAvailable, title, body)
    }

    // MARK: Offline (scheduled — fires even if the app is suspended)

    /// (Re)arm the 30-minute offline alarm. Call on every status received; the
    /// timer resets so it only fires after a genuine 30-minute reporting gap.
    func scheduleOffline(after seconds: TimeInterval = 30 * 60) {
        cancelOffline()
        guard NotificationSettings.isEnabled(.offline) else { return }
        let content = UNMutableNotificationContent()
        content.title = "📴 Spa Offline"
        content.body  = "The spa hasn't reported in for 30 minutes. It may have lost power or Wi-Fi."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: offlineID, content: content, trigger: trigger))
    }

    func cancelOffline() {
        center.removePendingNotificationRequests(withIdentifiers: [offlineID])
    }

    // MARK: Plumbing

    private func fire(_ category: NotificationCategory, _ title: String, _ body: String) {
        guard NotificationSettings.isEnabled(category) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        // Unique id per event → each transition surfaces its own notification.
        let id = "\(category.rawValue)-\(Date().timeIntervalSince1970)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - SpaAlertSink
// Adapts the monitor's decisions to the concrete notification posts.
extension NotificationManager: SpaAlertSink {
    func reachedTarget(temp: Int)  { postReachedTarget(temp: temp) }
    func freeze()                  { postFreeze() }
    func fault(code: Int)          { postFault(code: code) }
    func highTemp(code: Int)       { postHighTemp(code: code) }
    func sensorFault(temp: Int)    { postSensorFault(temp: temp) }
    func lowTemp()                 { postLowTemp() }
    func faultCleared()            { postFaultCleared() }
    func rearmOffline()            { scheduleOffline() }
}
