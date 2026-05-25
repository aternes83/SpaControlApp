import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var vm: SpaViewModel

    private var label: String {
        switch vm.connectionState {
        case .connected:       return "Connected"
        case .connecting:      return "Connecting…"
        case .disconnected:    return "Disconnected"
        case .error(let msg):  return msg
        }
    }

    private var dot: Color {
        switch vm.connectionState {
        case .connected:            return .green
        case .connecting:           return .yellow
        case .disconnected, .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundColor(dot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(dot.opacity(0.15))
        .clipShape(Capsule())
    }
}
