import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Multi-step wizard: pair the phone to the spa controller over Bluetooth, then
/// use that link to get the controller onto a WiFi network.
struct WiFiSetupWizardView: View {
    @StateObject private var ble = SpaBLEProvisioner()
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .connect
    @State private var chosenSSID = ""
    @State private var chosenSecured = true
    @State private var manualMode = false
    @State private var password = ""

    enum Step { case connect, chooseNetwork, password, provisioning, result }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()
                VStack(spacing: 20) {
                    StepIndicator(active: stepIndex)
                    content
                }
                .padding(24)
            }
            .navigationTitle("Wi‑Fi Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { finish() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { ble.start() }
        .onChange(of: ble.phase) { newPhase in
            if newPhase == .connected && step == .connect {
                step = .chooseNetwork
                ble.requestNetworkScan()
            }
        }
        .onChange(of: ble.provision) { p in
            switch p {
            case .success, .failed: step = .result
            default: break
            }
        }
    }

    private var stepIndex: Int {
        switch step {
        case .connect: return 0
        case .chooseNetwork, .password: return 1
        case .provisioning, .result: return 2
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .connect:      connectStep
        case .chooseNetwork: chooseStep
        case .password:     passwordStep
        case .provisioning: provisioningStep
        case .result:       resultStep
        }
    }

    // MARK: - Step 1: pair over Bluetooth

    private var connectStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: connectIcon)
                .font(.system(size: 60)).foregroundColor(Theme.water)
            Text(connectTitle).font(.title3).fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(connectSubtitle).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if ble.phase == .scanning || ble.phase == .connecting {
                ProgressView().tint(Theme.water).padding(.top, 4)
            }
            if ble.phase == .poweredOff || ble.phase == .unauthorized {
                Button("Open Settings") { openSystemSettings() }
                    .buttonStyle(.borderedProminent).tint(Theme.water)
            }
            if ble.phase == .disconnected {
                Button("Try Again") { ble.start() }
                    .buttonStyle(.borderedProminent).tint(Theme.water)
            }
            Spacer()
        }
    }

    private var connectIcon: String {
        switch ble.phase {
        case .connected:   return "checkmark.circle.fill"
        case .poweredOff, .unauthorized, .unsupported: return "exclamationmark.triangle.fill"
        case .disconnected: return "wifi.exclamationmark"
        default:           return "dot.radiowaves.left.and.right"
        }
    }
    private var connectTitle: String {
        switch ble.phase {
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .poweredOff:   return "Bluetooth is off"
        case .unauthorized: return "Bluetooth access needed"
        case .unsupported:  return "Bluetooth unavailable"
        case .disconnected: return "Lost connection"
        default:            return "Looking for your spa…"
        }
    }
    private var connectSubtitle: String {
        switch ble.phase {
        case .poweredOff:   return "Turn on Bluetooth to set up the spa's Wi‑Fi."
        case .unauthorized: return "Allow Bluetooth for SpaControl in Settings, then return here."
        case .unsupported:  return "This device can't use Bluetooth Low Energy."
        case .disconnected: return "The spa controller went out of range or powered off."
        default:            return "Make sure the spa controller is powered on and within a few feet."
        }
    }

    // MARK: - Step 2: choose network

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a Wi‑Fi network").font(.headline)
            if ble.provision == .scanningNetworks {
                Spacer()
                HStack { Spacer(); ProgressView("Scanning…").tint(Theme.water); Spacer() }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ble.networks) { net in
                            Button { select(net) } label: { NetworkRow(net: net) }
                        }
                        Button {
                            manualMode = true; chosenSSID = ""; chosenSecured = true
                            password = ""; step = .password
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Other network…")
                                Spacer()
                            }
                            .padding()
                            .background(Theme.card).cornerRadius(12)
                        }
                        .foregroundColor(Theme.water)
                    }
                }
                Button { ble.requestNetworkScan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .foregroundColor(Theme.water)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func select(_ net: WiFiNetwork) {
        chosenSSID = net.ssid
        chosenSecured = net.secured
        manualMode = false
        password = ""
        if net.secured { step = .password } else { connect() }
    }

    // MARK: - Step 3: password

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(manualMode ? "Enter network details" : chosenSSID)
                .font(.headline)
            if manualMode {
                TextField("Network name (SSID)", text: $chosenSSID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding().background(Theme.card).cornerRadius(12)
            }
            SecureField(manualMode ? "Password (leave blank if open)" : "Password", text: $password)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding().background(Theme.card).cornerRadius(12)

            Button { connect() } label: {
                Text("Connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.water)
            .disabled(connectDisabled)

            Button("Back") { step = .chooseNetwork }
                .foregroundColor(.secondary).frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var connectDisabled: Bool {
        if chosenSSID.isEmpty { return true }
        if !manualMode && chosenSecured && password.isEmpty { return true }
        return false
    }

    private func connect() {
        step = .provisioning
        ble.provisionWiFi(ssid: chosenSSID, password: password)
    }

    // MARK: - Step 4: provisioning

    private var provisioningStep: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(Theme.water).scaleEffect(1.4)
            Text("Connecting the spa to “\(chosenSSID)”…")
                .font(.headline).multilineTextAlignment(.center)
            Text("This can take up to 20 seconds.")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Step 5: result

    @ViewBuilder private var resultStep: some View {
        if case .success(let ip) = ble.provision {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64)).foregroundColor(Theme.good)
                Text("Connected!").font(.title3).fontWeight(.semibold)
                Text("The spa joined “\(chosenSSID)”.")
                    .foregroundColor(.secondary).multilineTextAlignment(.center)
                if !ip.isEmpty {
                    Text("IP \(ip)").font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Button { finish() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.good).padding(.top, 8)
                Spacer()
            }
        } else {
            let reason = { if case .failed(let r) = ble.provision { return r } else { return "" } }()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64)).foregroundColor(Theme.fault)
                Text("Couldn't connect").font(.title3).fontWeight(.semibold)
                Text(failureMessage(reason))
                    .foregroundColor(.secondary).multilineTextAlignment(.center)
                Button { step = .chooseNetwork; ble.requestNetworkScan() } label: {
                    Text("Try Again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.water).padding(.top, 8)
                Button("Close") { finish() }.foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func failureMessage(_ reason: String) -> String {
        switch reason {
        case "timeout": return "The spa couldn't join that network. Double-check the password and that the signal reaches the spa."
        case "save":    return "The spa couldn't save the settings. Please try again."
        default:        return "Something went wrong (\(reason)). Please try again."
        }
    }

    // MARK: - Helpers

    private func finish() {
        ble.stop()
        dismiss()
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Subviews

private struct NetworkRow: View {
    let net: WiFiNetwork
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi", variableValue: Double(net.bars) / 3.0)
                .foregroundColor(Theme.water).frame(width: 22)
            Text(net.ssid).foregroundColor(.white).lineLimit(1)
            Spacer()
            if net.secured {
                Image(systemName: "lock.fill").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Theme.card).cornerRadius(12)
    }
}

private struct StepIndicator: View {
    let active: Int
    private let labels = ["Pair", "Network", "Connect"]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= active ? Theme.water : Color.white.opacity(0.15))
                    .frame(height: 4)
            }
        }
    }
}

#if DEBUG
#Preview("Network row") {
    ZStack {
        Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()
        VStack(spacing: 10) {
            NetworkRow(net: WiFiNetwork(ssid: "HomeNet 5G", rssi: -52, secured: true))
            NetworkRow(net: WiFiNetwork(ssid: "Guest", rssi: -68, secured: false))
            NetworkRow(net: WiFiNetwork(ssid: "FarAway", rssi: -80, secured: true))
        }.padding()
    }
}
#endif
