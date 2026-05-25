import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: SpaViewModel
    @State private var showSettings = false

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
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .onAppear {
            if BrokerSettings.host.isEmpty {
                showSettings = true
            } else {
                vm.connect()
            }
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
