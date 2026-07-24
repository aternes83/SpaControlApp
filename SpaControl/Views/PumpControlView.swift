import SwiftUI

struct PumpControlView: View {
    @EnvironmentObject var vm: SpaViewModel

    /// The controller forces Pump 1 on to circulate water for the heater whenever
    /// the spa is below setpoint, so turning it "Off" has no effect then.
    private var callingForHeat: Bool {
        guard let s = vm.status else { return false }
        return s.tempF < s.setpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PUMPS")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Pump 1 — three-speed segmented control (Off disabled while heating)
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "water.waves").foregroundColor(.teal)
                    Text("Pump 1").foregroundColor(.white)
                    Spacer()
                    if callingForHeat {
                        Label("Heating", systemImage: "flame.fill")
                            .font(.caption2).foregroundColor(.orange)
                    } else {
                        Text(["Off", "Low", "High"][vm.status?.pump1 ?? 0])
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Pump1Segmented(current: vm.status?.pump1 ?? 0,
                               offDisabled: callingForHeat) {
                    vm.sendCommand(SpaCommand(pump1: $0))
                }
                if callingForHeat {
                    Text("Pump stays on to circulate water while heating.")
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(Color(red: 0.14, green: 0.20, blue: 0.28))
            .cornerRadius(12)

            // Pump 2 & 3 — tap-to-toggle cards
            HStack(spacing: 12) {
                PumpToggleCard(label: "Pump 2",
                               isOn: vm.status?.pump2 ?? false) {
                    vm.sendCommand(SpaCommand(pump2: $0))
                }
                PumpToggleCard(label: "Pump 3",
                               isOn: vm.status?.pump3 ?? false) {
                    vm.sendCommand(SpaCommand(pump3: $0))
                }
            }
        }
    }
}

/// Off/Low/High segmented control where the "Off" segment can be disabled
/// (SwiftUI's segmented Picker can't disable an individual segment).
struct Pump1Segmented: View {
    let current: Int
    let offDisabled: Bool
    let onSelect: (Int) -> Void

    private let segments = [(0, "Off"), (1, "Low"), (2, "High")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.0) { value, label in
                let selected = current == value
                let disabled = value == 0 && offDisabled
                Button { onSelect(value) } label: {
                    Text(label)
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(disabled ? Color.white.opacity(0.25)
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
    }
}

struct PumpToggleCard: View {
    let label: String
    let isOn: Bool
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
    }
}
