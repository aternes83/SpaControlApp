import Foundation

/// Checks a small remote manifest for newer app or controller-firmware versions
/// and raises a notification when one is available. The manifest is a static
/// JSON file the maintainer bumps on each release:
///
///   { "app":      { "latest": "1.1.0" },
///     "firmware": { "latest": "1.1.0" } }
///
/// Detection is de-duplicated per version, so each release notifies at most once.
enum UpdateChecker {
    /// Point this at wherever release metadata is published (e.g. a GitHub raw
    /// URL). Unreachable / missing → the check silently no-ops.
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/aternes83/SpaControlApp/main/updates.json")

    private struct Manifest: Decodable {
        struct Channel: Decodable { let latest: String }
        let app: Channel?
        let firmware: Channel?
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Fetch the manifest and notify if the app or the given firmware is behind.
    /// `firmwareVersion` comes from the controller's status (`fw`); pass nil if unknown.
    static func check(firmwareVersion: String?) {
        guard NotificationSettings.isEnabled(.updateAvailable),
              let url = manifestURL else { return }

        Task {
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return }

            if let latest = m.app?.latest, isNewer(latest, than: appVersion) {
                notifyOnce(kind: "app", version: latest,
                           title: "⬆️ App Update Available",
                           body: "SpaControl \(latest) is available. Update in the App Store.")
            }
            if let fw = firmwareVersion, let latest = m.firmware?.latest, isNewer(latest, than: fw) {
                notifyOnce(kind: "firmware", version: latest,
                           title: "⬆️ Controller Update Available",
                           body: "Spa controller firmware \(latest) is available (installed \(fw)).")
            }
        }
    }

    /// Notify at most once per (kind, version).
    private static func notifyOnce(kind: String, version: String, title: String, body: String) {
        let key = "update.notified.\(kind)"
        if UserDefaults.standard.string(forKey: key) == version { return }
        UserDefaults.standard.set(version, forKey: key)
        DispatchQueue.main.async {
            NotificationManager.shared.postUpdateAvailable(title: title, body: body)
        }
    }

    /// Numeric dotted-version compare: true if `a` is strictly newer than `b`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
