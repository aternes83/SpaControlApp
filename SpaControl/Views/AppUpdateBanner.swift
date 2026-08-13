import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// In-app banner shown when a newer version of THIS app is on the App Store.
/// iOS apps can't self-update (Apple only allows App Store / TestFlight), so the
/// "over-the-air" story for the phone app is: detect the new version from the
/// release manifest and deep-link the user to the store. (The spa *controller*
/// updates itself over MQTT — see FirmwareUpdateView.)
struct AppUpdateBanner: View {
    @StateObject private var model = Model()

    var body: some View {
        Group {
            if let v = model.available {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(Theme.water)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("App update available")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                        Text("Version \(v) is on the App Store")
                            .font(.caption).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Button("Update") { model.openAppStore() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.water)
                }
                .padding(12)
                .background(Theme.card)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 6)
            }
        }
        .onAppear { model.check() }
    }

    @MainActor
    final class Model: ObservableObject {
        @Published var available: String?

        /// The app's numeric App Store ID. Set this once the app is published so
        /// the Update button opens the correct product page.
        static let appStoreID = "0000000000"

        private struct ManifestApp: Decodable {
            struct Channel: Decodable { let latest: String }
            let app: Channel?
        }

        func check() {
            guard let url = UpdateChecker.manifestURL else { return }
            Task {
                let latest: String? = await {
                    guard let (data, resp) = try? await URLSession.shared.data(from: url),
                          (resp as? HTTPURLResponse)?.statusCode == 200,
                          let m = try? JSONDecoder().decode(ManifestApp.self, from: data),
                          let l = m.app?.latest,
                          UpdateChecker.isNewer(l, than: UpdateChecker.appVersion) else { return nil }
                    return l
                }()
                self.available = latest
            }
        }

        func openAppStore() {
            #if canImport(UIKit)
            // itms-apps opens the App Store app directly; falls back to https.
            let candidates = [
                "itms-apps://itunes.apple.com/app/id\(Self.appStoreID)",
                "https://apps.apple.com/app/id\(Self.appStoreID)",
            ]
            for s in candidates {
                if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url); return
                }
            }
            #endif
        }
    }
}
