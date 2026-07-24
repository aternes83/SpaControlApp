import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var vm: SpaViewModel

    /// Connected but the status feed has frozen — surfaced as an amber "Stale"
    /// state so the nav-bar dot never shows a reassuring green over dead data.
    private var isStaleConnected: Bool {
        if case .connected = vm.connectionState { return vm.isStale }
        return false
    }

    private var label: String {
        if isStaleConnected { return "Stale" }
        switch vm.connectionState {
        case .connected:       return "Connected"
        case .connecting:      return "Connecting…"
        case .disconnected:    return "Disconnected"
        case .error(let msg):  return msg
        }
    }

    private var dot: Color {
        if isStaleConnected { return .orange }
        switch vm.connectionState {
        case .connected:            return .green
        case .connecting:           return .yellow
        case .disconnected, .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label)
                .font(.caption).fontWeight(.medium)
                .foregroundColor(dot)
                .lineLimit(1)
        }
        .fixedSize()   // don't let the nav bar compress/truncate the label
    }
}
