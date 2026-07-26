import SwiftUI

/// Per-category on/off switches for the spa alerts. Backed by
/// `NotificationSettings` (UserDefaults); every category defaults to ON.
struct NotificationSettingsView: View {
    var body: some View {
        Form {
            Section(footer: Text("Alerts are delivered as local notifications while the app is open or running in the background. Enable notifications for SpaControl in iOS Settings to receive them.")) {
                ForEach(NotificationCategory.allCases) { category in
                    NotificationToggleRow(category: category)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
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
            // Turning off "offline" should also clear any pending 30-min alarm.
            if category == .offline && !newValue {
                NotificationManager.shared.cancelOffline()
            }
        }
    }
}

#if DEBUG
#Preview("Notifications") {
    NavigationView { NotificationSettingsView() }
}
#endif
