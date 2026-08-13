import SwiftUI

/// Controller firmware over-the-air update. Shows the running version, offers an
/// available update, and drives the install: the board downloads + verifies +
/// applies + reboots, with automatic rollback if the new build won't run. We
/// track progress from the status stream (`ota_state`, `fw`) and the connection.
struct FirmwareUpdateView: View {
    @EnvironmentObject var vm: SpaViewModel

    @State private var phase: Phase = .ready
    @State private var target: String = ""
    @State private var deadline: Date?

    /// Generous window covering fetch + reboot + up to a few rollback attempts.
    private let installTimeout: TimeInterval = 360

    enum Phase { case ready, updating, done, failed, rolledBack }

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentFw: String { vm.status?.fw ?? "—" }
    private var otaState: String { vm.status?.otaState ?? "idle" }
    private var availableVersion: String? {
        guard let a = vm.status?.otaAvail, !a.isEmpty, a != vm.status?.fw else { return nil }
        return a
    }

    var body: some View {
        ZStack {
            Theme.screenBg.ignoresSafeArea()
            VStack(spacing: 20) {
                versionCard
                content
                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Controller Firmware")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onChange(of: vm.status?.fw) { fw in
            if phase == .updating, let fw, fw == target { phase = .done; deadline = nil }
        }
        .onChange(of: vm.status?.otaState) { s in
            if phase == .updating, s == "error" { phase = .failed; deadline = nil }
        }
        .onReceive(tick) { _ in
            if phase == .updating, let dl = deadline, Date() >= dl {
                // Didn't reach the target version in time → the board kept/rolled
                // back to a known-good build (which is running normally).
                phase = (vm.status?.fw == target) ? .done : .rolledBack
                deadline = nil
            }
        }
    }

    // MARK: - Version card

    private var versionCard: some View {
        VStack(spacing: 6) {
            Text("INSTALLED VERSION").font(.caption2).kerning(1.2).foregroundColor(Theme.muted)
            Text(currentFw)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.water)
            if vm.connectionState != .connected {
                Label("Spa offline", systemImage: "wifi.slash")
                    .font(.caption).foregroundColor(Theme.stale)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Theme.card).cornerRadius(14)
    }

    // MARK: - Content by phase

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready:      readyContent
        case .updating:   updatingContent
        case .done:       resultContent(icon: "checkmark.seal.fill", tint: Theme.good,
                                        title: "Up to date",
                                        body: "The controller is running \(currentFw).")
        case .failed:     resultContent(icon: "xmark.octagon.fill", tint: Theme.fault,
                                        title: "Update failed",
                                        body: "The download couldn't be verified, so the spa kept its current version and is running normally.")
        case .rolledBack: resultContent(icon: "arrow.uturn.backward.circle.fill", tint: Theme.stale,
                                        title: "Rolled back safely",
                                        body: "The new version didn't start cleanly, so the spa automatically restored its previous working version (\(currentFw)).")
        }
    }

    @ViewBuilder private var readyContent: some View {
        if let v = availableVersion {
            VStack(spacing: 14) {
                Label("Update available", systemImage: "arrow.down.circle.fill")
                    .font(.headline).foregroundColor(Theme.water)
                Text("Version \(v) is ready to install.")
                    .foregroundColor(Theme.muted).multilineTextAlignment(.center)
                Text("The spa will download it, restart, and come back on its own — about a minute. If anything goes wrong it rolls back automatically.")
                    .font(.caption).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                Button { startUpdate(v) } label: {
                    Text("Install \(v)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.water)
                .disabled(vm.connectionState != .connected)
                if vm.connectionState != .connected {
                    Text("Connect to the spa to install.").font(.caption).foregroundColor(Theme.stale)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundColor(Theme.good)
                Text("You're up to date").font(.headline)
                Text("No newer controller firmware is available.")
                    .font(.subheadline).foregroundColor(Theme.muted)
            }.padding(.top, 8)
        }
    }

    private var updatingContent: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.water).scaleEffect(1.3)
            Text(updatingTitle).font(.headline).multilineTextAlignment(.center)
            Text("Installing \(target). Keep the spa powered — it will restart automatically. Don't close the app.")
                .font(.caption).foregroundColor(Theme.muted).multilineTextAlignment(.center)
        }.padding(.top, 8)
    }

    private var updatingTitle: String {
        if vm.connectionState != .connected { return "Spa restarting…" }
        switch otaState {
        case "fetching": return "Downloading update…"
        case "applying": return "Installing…"
        default:         return "Starting update…"
        }
    }

    private func resultContent(icon: String, tint: Color, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 56)).foregroundColor(tint)
            Text(title).font(.title3).fontWeight(.semibold)
            Text(body).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            Button("Done") { phase = .ready }
                .buttonStyle(.bordered).tint(Theme.water).padding(.top, 4)
        }.padding(.top, 8)
    }

    // MARK: - Actions

    private func startUpdate(_ version: String) {
        guard vm.sendOtaApply(version) else { return }
        target = version
        phase = .updating
        deadline = Date().addingTimeInterval(installTimeout)
    }
}
