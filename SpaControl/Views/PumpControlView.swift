import SwiftUI

struct PumpControlView: View {
    @EnvironmentObject var vm: SpaViewModel

    /// The controller forces Pump 1 on to circulate water for the heater whenever
    /// the spa is below setpoint, so turning it "Off" has no effect then.
    private var callingForHeat: Bool {
        guard let s = vm.status else { return false }
        return s.tempF < s.setpoint
    }

    /// Eco and Max Jet modes override the pumps entirely (Eco → Jet 1 low / Jets
    /// 2-3 off; Max Jet → all high), so the pump controls are locked while active.
    private var lockMode: String? {
        if vm.status?.maxJet == true { return "Max Jets" }
        if vm.status?.eco == true { return "Eco Mode" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PUMPS")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Pump 1 — three-speed segmented control
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "water.waves").foregroundColor(.teal)
                    Text("Pump 1").foregroundColor(.white)
                    Spacer()
                    header
                }
                Pump1Segmented(current: vm.status?.pump1 ?? 0,
                               offDisabled: callingForHeat,
                               allDisabled: lockMode != nil) {
                    vm.sendCommand(SpaCommand(pump1: $0))
                }
                if let mode = lockMode {
                    caption("Pumps are controlled by \(mode).")
                } else if callingForHeat {
                    caption("Pump stays on to circulate water while heating.")
                }
            }
            .padding()
            .background(Color(red: 0.14, green: 0.20, blue: 0.28))
            .cornerRadius(12)

            // Pump 2 & 3 — tap-to-toggle cards
            HStack(spacing: 12) {
                PumpToggleCard(label: "Pump 2",
                               isOn: vm.status?.pump2 ?? false,
                               disabled: lockMode != nil) {
                    vm.sendCommand(SpaCommand(pump2: $0))
                }
                PumpToggleCard(label: "Pump 3",
                               isOn: vm.status?.pump3 ?? false,
                               disabled: lockMode != nil) {
                    vm.sendCommand(SpaCommand(pump3: $0))
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        if let mode = lockMode {
            Label(mode, systemImage: mode == "Max Jets" ? "flame.fill" : "leaf.fill")
                .font(.caption2)
                .foregroundColor(mode == "Max Jets" ? .orange : .green)
        } else if callingForHeat {
            Label("Heating", systemImage: "flame.fill")
                .font(.caption2).foregroundColor(.orange)
        } else {
            Text(["Off", "Low", "High"][vm.status?.pump1 ?? 0])
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Off/Low/High segmented control. The "Off" segment can be disabled (heating),
/// or the whole control locked (Eco / Max Jet) — SwiftUI's segmented Picker
/// can't disable individual segments.
struct Pump1Segmented: View {
    let current: Int
    let offDisabled: Bool
    var allDisabled: Bool = false
    let onSelect: (Int) -> Void

    private let segments = [(0, "Off"), (1, "Low"), (2, "High")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.0) { value, label in
                let selected = current == value
                let disabled = allDisabled || (value == 0 && offDisabled)
                Button { onSelect(value) } label: {
                    Text(label)
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(disabled && !selected ? Color.white.opacity(0.25)
                                         : selected ? .black : .white)
                        .background(selected ? Color.teal : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .opacity(allDisabled ? 0.6 : 1)
    }
}

struct PumpToggleCard: View {
    let label: String
    let isOn: Bool
    var disabled: Bool = false
    let onChange: (Bool) -> Void

    var body: some View {
        Button { onChange(!isOn) } label: {
            VStack(spacing: 8) {
                Image(systemName: "water.waves")
                    .font(.title2)
                    .foregroundColor(isOn ? .teal : .secondary)
                Text(label).font(.caption).foregroundColor(.white)
                Text(isOn ? "On" : "Off")
                    .font(.caption2)
                    .foregroundColor(isOn ? .teal : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(red: 0.14, green: 0.20, blue: 0.28))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isOn ? Color.teal.opacity(0.6) : Color.clear, lineWidth: 1.5))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }
}
