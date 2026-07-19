import Foundation
import UserNotifications

/// Local-notification helper for spa faults. Posts a notification when the board
/// reports a new fault (and when a fault clears), and shows notifications even
/// while the app is in the foreground.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    private var center: UNUserNotificationCenter { .current() }

    /// Register as delegate so foreground notifications still present as banners.
    /// Call once at launch.
    func configure() {
        center.delegate = self
    }

    /// Ask the user for alert/sound permission. Safe to call repeatedly — the
    /// system only prompts once, then returns the existing decision.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func postFault(code: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Spa Fault — \(FaultCode.shortLabel(code))"
        content.body  = FaultCode.description(code)
        content.sound = .default
        post(content, idPrefix: "spa-fault")
    }

    func postFaultCleared() {
        let content = UNMutableNotificationContent()
        content.title = "✅ Spa Fault Cleared"
        content.body  = "The spa is operating normally again."
        content.sound = .default
        post(content, idPrefix: "spa-fault-cleared")
    }

    private func post(_ content: UNMutableNotificationContent, idPrefix: String) {
        // Unique id per event → each transition surfaces its own notification;
        // nil trigger delivers immediately.
        let id = "\(idPrefix)-\(Date().timeIntervalSince1970)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
