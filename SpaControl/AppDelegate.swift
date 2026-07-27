import UIKit

/// Minimal app delegate, bridged into the SwiftUI app via
/// `@UIApplicationDelegateAdaptor`, solely to receive the APNs device token
/// (SwiftUI has no native hook for remote-notification registration).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.setDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.setRegistrationError(error)
    }
}
