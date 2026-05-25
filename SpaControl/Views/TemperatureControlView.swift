import SwiftUI

struct TemperatureControlView: View {
    @EnvironmentObject var vm: SpaViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Current temperature
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(vm.status.map { String(format: "%.1f", $0.tempF) } ?? "--")
                    .font(.system(size: 72, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                Text("°F")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            // Heater status
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.status?.heater == true ? Color.orange : Color.gray.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(vm.status?.heater == true ? "Heating" : "Idle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider().background(Color.white.opacity(0.15))

            // Setpoint ±
            HStack(spacing: 32) {
                Button {
                    let sp = vm.status?.setpoint ?? 100
                    vm.sendCommand(SpaCommand(setTemp: max(60, sp - 1)))
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.teal)
                }

                VStack(spacing: 2) {
                    Text(vm.status.map { String(format: "%.0f°", $0.setpoint) } ?? "--°")
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    Text("Setpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    let sp = vm.status?.setpoint ?? 100
                    vm.sendCommand(SpaCommand(setTemp: min(106, sp + 1)))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.teal)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(red: 0.14, green: 0.20, blue: 0.28))
        .cornerRadius(16)
    }
}
