import SwiftUI

/// Per-category on/off switches for the spa alerts, plus optional push-service
/// configuration. Backed by `NotificationSettings` (UserDefaults); every
/// category defaults to ON. When a push service URL is set, alerts are delivered
/// in the background via Apple Push; otherwise they're local, foreground-only.
struct NotificationSettingsView: View {
    @AppStorage(PushManager.urlKey) private var pushURL = ""
    @AppStorage(PushManager.tokenKey) private var pushToken = ""
    @ObservedObject private var push = PushManager.shared
    @State private var previousURL = ""

    var body: some View {
        Form {
            Section {
                TextField("Service URL (https://…)", text: $pushURL)
                    .keyboardType(.URL).autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(applyPushConfig)
                SecureField("API token", text: $pushToken)
                    .onSubmit(applyPushConfig)
                HStack {
                    Label(push.isActive ? "Background push" : "On-device only",
                          systemImage: push.isActive ? "bolt.horizontal.fill" : "iphone")
                    Spacer()
                    Text(push.isActive ? (push.lastRegistration ?? "Registering…") : "App must be open")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Delivery")
            } footer: {
                Text("Leave the URL blank for on-device alerts (delivered only while the app is open or briefly backgrounded). Set your push service URL to receive alerts in the background via Apple Push, even when the app is closed.")
            }

            Section {
                ForEach(NotificationCategory.allCases) { category in
                    NotificationToggleRow(category: category)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Enable notifications for SpaControl in iOS Settings to receive them.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            previousURL = pushURL
            if push.isActive { push.register() }
        }
    }

    private func applyPushConfig() {
        if pushURL.isEmpty {
            if !previousURL.isEmpty { push.unregister(from: previousURL) }
        } else {
            push.register()
        }
        previousURL = pushURL
    }
}

private struct NotificationToggleRow: View {
    let category: NotificationCategory
    @State private var isOn: Bool

    init(category: NotificationCategory) {
        self.category = category
        _isOn = State(initialValue: NotificationSettings.isEnabled(category))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                    Text(category.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .onChange(of: isOn) { newValue in
            NotificationSettings.setEnabled(category, newValue)
            if category == .offline && !newValue {
                NotificationManager.shared.cancelOffline()
            }
            // Keep the push service's per-device preferences in sync.
            PushManager.shared.register()
        }
    }
}

#if DEBUG
#Preview("Notifications") {
    NavigationView { NotificationSettingsView() }
}
#endif
