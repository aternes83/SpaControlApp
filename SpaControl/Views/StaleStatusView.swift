import SwiftUI

/// Prominent amber banner shown when the MQTT connection is up but the board's
/// status feed has gone stale (no fresh `spa/status` within `staleThreshold`).
/// Warns the user not to trust the displayed readings or act on them.
struct StaleStatusBanner: View {
    let lastUpdate: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Data may be out of date").bold()
                Text(subtitle).font(.caption)
            }
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.9))
        .foregroundColor(.black)
        .cornerRadius(12)
    }

    private var subtitle: String {
        guard let lastUpdate else { return "No update received yet" }
        return "Last update \(RelativeTime.string(since: lastUpdate))"
    }
}

/// Subtle, right-aligned caption showing how long ago the last status arrived.
/// Re-renders once per second via TimelineView so the age counts up live.
struct LastUpdatedLabel: View {
    @EnvironmentObject var vm: SpaViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(text(now: context.date))
            }
            .font(.caption2)
            .foregroundColor(vm.isStale ? .orange : .secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func text(now: Date) -> String {
        guard let last = vm.lastStatusDate else {
            return vm.connectionState == .connected ? "Awaiting data…" : "—"
        }
        return "Updated \(RelativeTime.string(since: last, now: now))"
    }
}

/// Compact, human-readable "time ago" formatting for status freshness.
enum RelativeTime {
    static func string(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 2  { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
