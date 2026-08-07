import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var vm: SpaViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BrokerSettings.hostKey)     private var host:     String = ""
    @AppStorage(BrokerSettings.portKey)     private var port:     Int    = 8883
    @AppStorage(BrokerSettings.usernameKey) private var username: String = ""
    @AppStorage(BrokerSettings.passwordKey) private var password: String = ""
    @AppStorage(BrokerSettings.deviceIdKey) private var deviceId: String = ""

    @State private var showWiFiWizard = false
    @State private var showCalWizard = false

    var body: some View {
        NavigationView {
            Form {
                Section("Spa Controller") {
                    Button {
                        showWiFiWizard = true
                    } label: {
                        Label("Set up spa Wi‑Fi over Bluetooth", systemImage: "wifi")
                    }
                    Button {
                        showCalWizard = true
                    } label: {
                        Label("Calibrate temperature sensor", systemImage: "thermometer.variable")
                    }
                }

                Section("Alerts") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }

                Section("Broker") {
                    TextField("Host", text: $host)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("8883", value: $port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                Section {
                    TextField("Device ID", text: $deviceId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Paired Spa")
                } footer: {
                    Text("Identifies which spa this app controls (set automatically during Bluetooth setup). Leave blank for a single legacy spa.")
                }

                Section {
                    Button("Connect") {
                        vm.connect()
                        dismiss()
                    }
                    .disabled(host.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showWiFiWizard) {
            WiFiSetupWizardView { success in
                if success {
                    // Spa is online now — reconnect and return to the dashboard.
                    if !host.isEmpty { vm.connect() }
                    dismiss()
                } else {
                    showWiFiWizard = false
                }
            }
        }
        .sheet(isPresented: $showCalWizard) {
            CalibrationWizardView { _ in showCalWizard = false }
                .environmentObject(vm)
        }
    }
}
