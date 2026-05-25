import SwiftUI

@main
struct SpaControlApp: App {
    @StateObject private var vm = SpaViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
        }
    }
}
