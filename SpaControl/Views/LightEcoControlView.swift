import SwiftUI

struct LightEcoControlView: View {
    @EnvironmentObject var vm: SpaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FEATURES")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                FeatureCard(label: "Light",
                            icon: "lightbulb.fill",
                            isOn: vm.status?.light ?? false,
                            activeColor: .yellow) {
                    vm.sendCommand(SpaCommand(light: $0))
                }

                // Eco and Max Jets are mutually exclusive — disable each while
                // the other is active.
                FeatureCard(label: "Eco Mode",
                            icon: "leaf.fill",
                            isOn: vm.status?.eco ?? false,
                            activeColor: .green,
                            disabled: vm.status?.maxJet ?? false) {
                    vm.sendCommand(SpaCommand(eco: $0))
                }

                FeatureCard(label: "Max Jets",
                            icon: "flame.fill",
                            isOn: vm.status?.maxJet ?? false,
                            activeColor: .orange,
                            disabled: vm.status?.eco ?? false) {
                    vm.sendCommand(SpaCommand(maxJet: $0))
                }
            }
        }
    }
}

struct FeatureCard: View {
    let label: String
    let icon: String
    let isOn: Bool
    let activeColor: Color
    var disabled: Bool = false
    let onChange: (Bool) -> Void

    var body: some View {
        Button { onChange(!isOn) } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isOn ? activeColor : .secondary)
                Text(label).font(.caption).foregroundColor(.white)
                Text(isOn ? "On" : "Off")
                    .font(.caption2)
                    .foregroundColor(isOn ? activeColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(red: 0.14, green: 0.20, blue: 0.28))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isOn ? activeColor.opacity(0.6) : Color.clear, lineWidth: 1.5))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
