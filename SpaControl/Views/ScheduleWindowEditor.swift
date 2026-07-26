import SwiftUI

/// Edits a single heat window: which days, the start/end time, and the target
/// temperature. Commits back through `onSave` on Done.
struct ScheduleWindowEditor: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ScheduleWindow) -> Void

    @State private var days: Set<Int>
    @State private var start: Date
    @State private var end: Date
    @State private var tempF: Int
    private let windowID: UUID
    private let enabled: Bool

    init(window: ScheduleWindow, onSave: @escaping (ScheduleWindow) -> Void) {
        self.onSave = onSave
        self.windowID = window.id
        self.enabled = window.enabled
        _days  = State(initialValue: window.days)
        _start = State(initialValue: ScheduleTime.date(fromMinutes: window.startMinutes))
        _end   = State(initialValue: ScheduleTime.date(fromMinutes: window.endMinutes))
        _tempF = State(initialValue: window.tempF)
    }

    private var wraps: Bool {
        ScheduleTime.minutes(from: end) <= ScheduleTime.minutes(from: start)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.screenBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        daysCard
                        timeCard
                        tempCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Heat Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.disabled(days.isEmpty)
                }
            }
        }
    }

    private func save() {
        let w = ScheduleWindow(
            id: windowID,
            enabled: enabled,
            days: days,
            startMinutes: ScheduleTime.minutes(from: start),
            endMinutes: ScheduleTime.minutes(from: end),
            tempF: tempF
        )
        onSave(w)
        dismiss()
    }

    // MARK: Days

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAYS").font(.caption).fontWeight(.bold).tracking(1.1)
                .foregroundColor(Theme.muted)

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let on = days.contains(i)
                    Button {
                        if on { days.remove(i) } else { days.insert(i) }
                    } label: {
                        Text(ScheduleWeekday.short[i])
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Theme.water : Color.white.opacity(0.06))
                            .foregroundColor(on ? .black : .white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                presetChip("Every day", Set(0...6))
                presetChip("Weekdays", Set(0...4))
                presetChip("Weekends", Set([5, 6]))
            }
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func presetChip(_ title: String, _ set: Set<Int>) -> some View {
        Button { days = set } label: {
            Text(title)
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(days == set ? Theme.water.opacity(0.25) : Color.white.opacity(0.06))
                .foregroundColor(days == set ? Theme.water : Theme.muted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Time

    private var timeCard: some View {
        VStack(spacing: 12) {
            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
            Divider().overlay(Color.white.opacity(0.08))
            DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            if wraps {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill").font(.caption2)
                    Text("Ends the next morning (overnight window)").font(.caption)
                    Spacer()
                }
                .foregroundColor(Theme.muted)
            }
        }
        .foregroundColor(.white)
        .tint(Theme.water)
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    // MARK: Temperature

    private var tempCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HEAT TO").font(.caption).fontWeight(.bold).tracking(1.1)
                    .foregroundColor(Theme.muted)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.subheadline)
                    Text("\(tempF)°F")
                        .font(.system(.title2, design: .rounded)).bold()
                        .monospacedDigit()
                }
                .foregroundColor(Theme.heat)
            }
            Slider(
                value: Binding(get: { Double(tempF) }, set: { tempF = Int($0.rounded()) }),
                in: Double(Schedule.tempRange.lowerBound)...Double(Schedule.tempRange.upperBound),
                step: 1
            )
            .tint(Theme.heat)
            HStack {
                Text("\(Schedule.tempRange.lowerBound)°")
                Spacer()
                Text("\(Schedule.tempRange.upperBound)°")
            }
            .font(.caption2).foregroundColor(Theme.muted)
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }
}

#if DEBUG
#Preview("Editor") {
    ScheduleWindowEditor(
        window: ScheduleWindow(days: Set(0...4), startMinutes: 21*60, endMinutes: 6*60, tempF: 102)
    ) { _ in }
    .preferredColorScheme(.dark)
}
#endif
