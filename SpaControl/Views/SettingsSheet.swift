import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var vm: SpaViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BrokerSettings.hostKey)     private var host:     String = ""
    @AppStorage(BrokerSettings.portKey)     private var port:     Int    = 8883
    @AppStorage(BrokerSettings.usernameKey) private var username: String = ""
    @AppStorage(BrokerSettings.passwordKey) private var password: String = ""

    var body: some View {
        NavigationView {
            Form {
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
    }
}
