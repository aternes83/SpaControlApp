import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: SpaViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var showSettings = false
    @State private var showSchedule = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()

                if BrokerSettings.host.isEmpty {
                    SetupPromptView(showSettings: $showSettings)
                } else {
                    StatusDashboardView()
                }
            }
            .navigationTitle("SpaControl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionStatusView()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 18) {
                        Button { showSchedule = true } label: {
                            Image(systemName: vm.status?.scheduleActive == true
                                  ? "calendar.badge.clock" : "calendar")
                                .foregroundColor(scheduleStore.schedule.enabled ? Theme.water : nil)
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showSchedule) {
            ScheduleView()
        }
        .onAppear {
            NotificationManager.shared.requestAuthorization()
            if BrokerSettings.host.isEmpty {
                showSettings = true
            } else {
                vm.connect()
            }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "openSchedule") { showSchedule = true }
            #endif
        }
        .onChange(of: vm.connectionState) { state in
            // Sync the controller's persisted schedule with the app on every
            // (re)connect, so edits made offline take effect once we're back.
            if state == .connected { vm.sendSchedule(scheduleStore.dto) }
        }
    }
}

struct SetupPromptView: View {
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No broker configured")
                .font(.title2)
                .foregroundColor(.white)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
