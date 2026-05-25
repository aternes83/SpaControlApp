import SwiftUI

struct LightEcoControlView: View {
    @EnvironmentObject var vm: SpaViewModel
    @State private var maxJetActive = false

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

                FeatureCard(label: "Eco Mode",
                            icon: "leaf.fill",
                            isOn: vm.status?.eco ?? false,
                            activeColor: .green) {
                    vm.sendCommand(SpaCommand(eco: $0))
                }

                // Max Jets — command only; mirror the 20-min auto-off locally
                Button {
                    maxJetActive = true
                    vm.sendCommand(SpaCommand(maxJet: true))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1200) {
                        maxJetActive = false
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundColor(maxJetActive ? .orange : .secondary)
                        Text("Max Jets").font(.caption).foregroundColor(.white)
                        Text(maxJetActive ? "20 min" : "Off")
                            .font(.caption2)
                            .foregroundColor(maxJetActive ? .orange : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.14, green: 0.20, blue: 0.28))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(maxJetActive ? Color.orange.opacity(0.6) : Color.clear,
                                lineWidth: 1.5))
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
    }
}
