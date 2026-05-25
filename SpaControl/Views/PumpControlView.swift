import SwiftUI

struct PumpControlView: View {
    @EnvironmentObject var vm: SpaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PUMPS")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Pump 1 — three-speed segmented picker
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "water.waves").foregroundColor(.teal)
                    Text("Pump 1").foregroundColor(.white)
                    Spacer()
                    Text(["Off", "Low", "High"][vm.status?.pump1 ?? 0])
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Picker("Pump 1", selection: Binding(
                    get: { vm.status?.pump1 ?? 0 },
                    set: { vm.sendCommand(SpaCommand(pump1: $0)) }
                )) {
                    Text("Off").tag(0)
                    Text("Low").tag(1)
                    Text("High").tag(2)
                }
                .pickerStyle(.segmented)
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
