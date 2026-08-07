import SwiftUI

/// Temperature-sensor setup wizard. Two paths:
///  • pick a preset for a known spa-pack NTC (instant), or
///  • run a 2-point field calibration that fits any unknown retrofit sensor.
/// The resulting Beta-model coefficients are pushed to the controller and saved
/// as a reusable named profile.
struct CalibrationWizardView: View {
    var onFinish: (Bool) -> Void = { _ in }

    @EnvironmentObject var vm: SpaViewModel
    @StateObject private var store = CalProfileStore()

    @State private var step: Step = .method

    // 2-point capture
    @State private var r1: Double?
    @State private var t1Text: String = ""
    @State private var r2: Double?
    @State private var t2Text: String = ""

    // Result being reviewed / trimmed before saving
    @State private var workingCal: TempCalDTO?
    @State private var profileName: String = ""
    @State private var errorText: String?

    enum Step { case method, point1, point2, review, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.screenBg.ignoresSafeArea()
                VStack(spacing: 20) {
                    StepBar(active: stepIndex)
                    content
                }
                .padding(24)
            }
            .navigationTitle("Temperature Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onFinish(false) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var stepIndex: Int {
        switch step {
        case .method:            return 0
        case .point1, .point2:   return 1
        case .review, .done:     return 2
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .method:  methodStep
        case .point1:  capturePointStep(index: 1)
        case .point2:  capturePointStep(index: 2)
        case .review:  reviewStep
        case .done:    doneStep
        }
    }

    // MARK: - Live probe readout

    private var currentOhms: Double? {
        if let r = vm.status?.rOhms { return Double(r) }
        return nil
    }

    private var probeCard: some View {
        VStack(spacing: 6) {
            Text("PROBE RESISTANCE")
                .font(.caption2).kerning(1.2).foregroundColor(Theme.muted)
            if let r = currentOhms {
                Text(ohmsText(r))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.water)
                    .contentTransition(.numericText())
                Text(freshnessText)
                    .font(.caption2).foregroundColor(Theme.muted)
            } else {
                ProgressView().tint(Theme.water).padding(.vertical, 6)
                Text(vm.connectionState == .connected
                     ? "Waiting for a reading from the probe…"
                     : "Connect to the spa first.")
                    .font(.caption).foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.card).cornerRadius(14)
    }

    private var freshnessText: String {
        guard let last = vm.lastStatusDate else { return "" }
        let age = Int(Date().timeIntervalSince(last))
        if age <= 2 { return "updated just now" }
        return "updated \(age)s ago · settle, then wait for a fresh reading"
    }

    private func ohmsText(_ r: Double) -> String {
        r >= 1000 ? String(format: "%.2f kΩ", r / 1000) : String(format: "%.0f Ω", r)
    }

    // MARK: - Step: method

    private var methodStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                probeCard

                if vm.status?.faultCode == 5 {
                    Label("The probe reads open or shorted. Check the wiring before calibrating.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(Theme.stale)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.stale.opacity(0.12)).cornerRadius(10)
                }

                Text("Calibrate for accuracy")
                    .font(.headline)
                Text("A 2-point calibration works with any sensor — even an unknown one already in a retrofit spa.")
                    .font(.subheadline).foregroundColor(Theme.muted)

                Button { startTwoPoint() } label: {
                    HStack {
                        Image(systemName: "thermometer.variable.and.figure")
                        Text("Calibrate my sensor (2-point)")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding().background(Theme.water.opacity(0.16)).cornerRadius(12)
                    .foregroundColor(Theme.water)
                }

                if !store.profiles.isEmpty {
                    Text("SAVED PROFILES").font(.caption2).kerning(1.2)
                        .foregroundColor(Theme.muted).padding(.top, 4)
                    ForEach(store.profiles) { p in
                        Button { review(cal: p.cal, name: p.name) } label: {
                            calRow(title: p.name, detail: betaSummary(p.cal), icon: "bookmark.fill")
                        }
                    }
                }

                Text("KNOWN SENSOR").font(.caption2).kerning(1.2)
                    .foregroundColor(Theme.muted).padding(.top, 4)
                Text("Pick your spa pack if you know it — you can fine-tune later.")
                    .font(.caption).foregroundColor(Theme.muted)
                ForEach(TempCalibration.presets) { preset in
                    Button { review(cal: preset.cal, name: preset.name) } label: {
                        calRow(title: preset.name, detail: preset.detail, icon: "cpu")
                    }
                }
            }
        }
    }

    private func calRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(Theme.water).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(.white)
                Text(detail).font(.caption).foregroundColor(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.muted)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).cornerRadius(12)
    }

    // MARK: - Step: capture a point

    private func capturePointStep(index: Int) -> some View {
        let isFirst = index == 1
        let tText = isFirst ? $t1Text : $t2Text
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isFirst ? "Point 1 — first reading" : "Point 2 — second reading")
                    .font(.headline)
                Text(isFirst
                     ? "Put the probe and a reference thermometer in the same water. Wait about a minute for both to settle."
                     : "Change the water temperature by at least \(Int(TempCalibration.minSpreadF))°F (heat it, or use the spa at temperature) and let it settle again.")
                    .font(.subheadline).foregroundColor(Theme.muted)

                probeCard

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thermometer reading (°F)").font(.caption).foregroundColor(Theme.muted)
                    TextField("e.g. 78.5", text: tText)
                        .keyboardType(.decimalPad)
                        .padding().background(Theme.card).cornerRadius(12)
                        .foregroundColor(.white)
                }

                if let e = errorText {
                    Text(e).font(.caption).foregroundColor(Theme.fault)
                }

                Button { capture(index: index) } label: {
                    Text(isFirst ? "Capture point 1" : "Capture point 2 & solve")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.water)
                .disabled(!canCapture(text: tText.wrappedValue))

                Button("Back") { errorText = nil; step = isFirst ? .method : .point1 }
                    .foregroundColor(Theme.muted).frame(maxWidth: .infinity)
            }
        }
    }

    private func canCapture(text: String) -> Bool {
        currentOhms != nil && Double(text.replacingOccurrences(of: ",", with: ".")) != nil
    }

    // MARK: - Step: review

    @ViewBuilder private var reviewStep: some View {
        if let cal = workingCal {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Review calibration").font(.headline)

                    // Live sanity check: what the probe reads *now* with this curve.
                    VStack(spacing: 6) {
                        Text("PROBE READS NOW").font(.caption2).kerning(1.2).foregroundColor(Theme.muted)
                        if let r = currentOhms, let f = TempCalibration.tempF(fromOhms: r, cal: cal) {
                            Text(String(format: "%.1f°F", f))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.heat)
                            Text(ohmsText(r)).font(.caption).foregroundColor(Theme.muted)
                        } else {
                            Text("—").font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.card).cornerRadius(14)

                    // Fine trim
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fine trim").foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%+.1f°F", cal.offsetF))
                                .font(.system(.body, design: .monospaced)).foregroundColor(Theme.water)
                        }
                        Stepper("Offset", value: Binding(
                            get: { workingCal?.offsetF ?? 0 },
                            set: { workingCal?.offsetF = $0 }
                        ), in: -10...10, step: 0.1)
                        .labelsHidden()
                    }
                    .padding().background(Theme.card).cornerRadius(12)

                    Text(betaSummary(cal)).font(.caption).foregroundColor(Theme.muted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile name").font(.caption).foregroundColor(Theme.muted)
                        TextField("My Spa NTC", text: $profileName)
                            .padding().background(Theme.card).cornerRadius(12).foregroundColor(.white)
                    }

                    Button { save(cal) } label: {
                        Text("Save to spa").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.good)
                    .disabled(vm.connectionState != .connected)

                    if vm.connectionState != .connected {
                        Text("Connect to the spa to save this calibration.")
                            .font(.caption).foregroundColor(Theme.stale)
                    }

                    Button("Back") { step = .method }
                        .foregroundColor(Theme.muted).frame(maxWidth: .infinity)
                }
            }
        } else {
            Text("No calibration to review.").foregroundColor(Theme.muted)
        }
    }

    // MARK: - Step: done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundColor(Theme.good)
            Text("Calibration saved").font(.title3).fontWeight(.semibold)
            Text("The spa is now reading calibrated temperature and will keep this setting through reboots.")
                .font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            if let r = currentOhms, let cal = workingCal,
               let f = TempCalibration.tempF(fromOhms: r, cal: cal) {
                Text(String(format: "Now reading %.1f°F", f))
                    .font(.headline).foregroundColor(Theme.heat).padding(.top, 4)
            }
            Button { onFinish(true) } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(Theme.good).padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startTwoPoint() {
        r1 = nil; r2 = nil; t1Text = ""; t2Text = ""; errorText = nil
        step = .point1
    }

    private func capture(index: Int) {
        errorText = nil
        guard let r = currentOhms,
              let t = Double((index == 1 ? t1Text : t2Text).replacingOccurrences(of: ",", with: ".")) else { return }
        if index == 1 {
            r1 = r
            step = .point2
        } else {
            guard let firstR = r1, let firstT = Double(t1Text.replacingOccurrences(of: ",", with: ".")) else {
                errorText = "Point 1 is missing — start over."
                step = .point1
                return
            }
            if abs(t - firstT) < TempCalibration.minSpreadF {
                errorText = "The two readings are only \(String(format: "%.1f", abs(t - firstT)))°F apart. Spread them at least \(Int(TempCalibration.minSpreadF))°F for an accurate fit."
                return
            }
            r2 = r
            guard let cal = TempCalibration.solve(r1: firstR, tF1: firstT, r2: r, tF2: t) else {
                errorText = "Couldn't solve a curve from those points. Re-check the thermometer readings and try again."
                return
            }
            review(cal: cal, name: "My Spa NTC")
        }
    }

    private func review(cal: TempCalDTO, name: String) {
        workingCal = cal
        profileName = name
        errorText = nil
        step = .review
    }

    private func save(_ cal: TempCalDTO) {
        let final = workingCal ?? cal
        guard vm.sendCalibration(final) else { return }
        let name = profileName.trimmingCharacters(in: .whitespaces)
        store.add(CalProfile(name: name.isEmpty ? "My Spa NTC" : name, cal: final))
        step = .done
    }

    private func betaSummary(_ cal: TempCalDTO) -> String {
        String(format: "β %.0f K · R₀ %.0f Ω @ %.0f°C · R_fixed %.0f Ω",
               cal.beta, cal.r0, cal.t0C, cal.rFixed)
    }
}

// MARK: - Step indicator

private struct StepBar: View {
    let active: Int
    private let labels = ["Method", "Measure", "Save"]
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
