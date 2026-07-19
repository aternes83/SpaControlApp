import SwiftUI

@main
struct SpaControlApp: App {
    @StateObject private var vm = SpaViewModel()

    init() {
        // Register the notification delegate so fault alerts present even while
        // the app is in the foreground.
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
        }
    }
}
