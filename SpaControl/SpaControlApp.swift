import SwiftUI

@main
struct SpaControlApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = SpaViewModel()
    @StateObject private var scheduleStore = ScheduleStore()

    init() {
        // Register the notification delegate so fault alerts present even while
        // the app is in the foreground.
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(scheduleStore)
                .preferredColorScheme(.dark)
        }
    }
}
