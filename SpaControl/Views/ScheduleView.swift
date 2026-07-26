import SwiftUI

/// Smart-schedule screen. Lets the user define recurring heat windows so the spa
/// only heats during chosen hours — the Time-of-Day use case: heat to a comfort
/// temperature during off-peak utility hours and coast at a lower hold temp the
/// rest of the time. The controller enforces the schedule on its own clock.
struct ScheduleView: View {
    @EnvironmentObject var vm: SpaViewModel
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ScheduleWindow?

    private func push() { vm.sendSchedule(store.dto) }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.screenBg.ignoresSafeArea()
                content
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { push(); dismiss() }
                }
            }
            .sheet(item: $editing) { window in
                ScheduleWindowEditor(window: window) { saved in
                    store.update(saved)
                    push()
                }
                .environmentObject(store)
            }
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openEditor"),
                   let first = store.schedule.windows.first {
                    editing = first
                }
            }
            #endif
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                masterCard

                if store.schedule.enabled {
                    if vm.status?.scheduleActive == true {
                        activeBanner
                    }
                    offPeakCard
                    windowsSection
                }
            }
            .padding()
        }
    }

    // MARK: Master enable

    private var masterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { store.schedule.enabled },
                set: { store.schedule.enabled = $0; push() }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(Theme.water)
                    Text("Smart Schedule").fontWeight(.semibold)
                }
            }
            .tint(Theme.good)

            Text("Heat only during the hours you choose — ideal for Time-of-Day utility plans. Outside your windows the spa holds at the off-peak temperature.")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    private var activeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").foregroundColor(Theme.heat)
            Text("Heat window active now").fontWeight(.semibold)
            Spacer()
        }
        .font(.subheadline)
        .padding()
        .background(Theme.heat.opacity(0.18))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.heat.opacity(0.4), lineWidth: 1))
        .foregroundColor(.white)
        .cornerRadius(12)
    }

    // MARK: Off-peak hold temp

    private var offPeakCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Off-peak hold").fontWeight(.semibold).foregroundColor(.white)
                    Text("Target when no window is active")
                        .font(.caption).foregroundColor(Theme.muted)
                }
                Spacer()
                Text("\(store.schedule.offTempF)°F")
                    .font(.system(.title3, design: .rounded)).bold()
                    .foregroundColor(Theme.water)
                    .monospacedDigit()
                    .frame(minWidth: 62, alignment: .trailing)
                Stepper("Off-peak hold", value: Binding(
                    get: { store.schedule.offTempF },
                    set: { store.schedule.offTempF = $0 }
                ), in: Schedule.offTempRange, step: 1, onEditingChanged: { editing in
                    if !editing { push() }
                })
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    // MARK: Windows

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HEAT WINDOWS")
                    .font(.caption).fontWeight(.bold).tracking(1.1)
                    .foregroundColor(Theme.muted)
                Spacer()
                Button {
                    let w = ScheduleWindow()
                    store.schedule.windows.append(w)
                    editing = w
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
                .tint(Theme.water)
            }

            if store.schedule.windows.isEmpty {
                Text("No windows yet. Add one to pick the days, hours, and temperature the spa should heat to.")
                    .font(.caption).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.card.opacity(0.5))
                    .cornerRadius(12)
            } else {
                ForEach(store.schedule.windows) { window in
                    WindowRow(window: window,
                              onToggle: { on in
                                  var w = window; w.enabled = on
                                  store.update(w); push()
                              },
                              onTap: { editing = window },
                              onDelete: {
                                  store.schedule.windows.removeAll { $0.id == window.id }
                                  push()
                              })
                }
            }
        }
    }
}

/// One heat-window summary row: enable toggle, time range, days, and target.
private struct WindowRow: View {
    let window: ScheduleWindow
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { window.enabled }, set: onToggle))
                .labelsHidden()
                .tint(Theme.good)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(ScheduleTime.label(window.startMinutes)) – \(ScheduleTime.label(window.endMinutes))")
                            .fontWeight(.semibold)
                            .foregroundColor(window.enabled ? .white : Theme.muted)
                        if window.wrapsMidnight {
                            Text("+1d").font(.caption2).foregroundColor(Theme.muted)
                        }
                    }
                    Text(ScheduleWeekday.summary(window.days))
                        .font(.caption).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                Image(systemName: "flame.fill").font(.caption2)
                Text("\(window.tempF)°").monospacedDigit().fontWeight(.semibold)
            }
            .foregroundColor(window.enabled ? Theme.heat : Theme.muted)

            Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.muted)
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
        .opacity(window.enabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .swipeActions {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

#if DEBUG
#Preview("Schedule") {
    let store = ScheduleStore()
    store.schedule = Schedule(enabled: true, offTempF: 80, windows: [
        ScheduleWindow(enabled: true, days: Set(0...4), startMinutes: 21*60, endMinutes: 6*60, tempF: 102),
        ScheduleWindow(enabled: false, days: [5, 6], startMinutes: 8*60, endMinutes: 11*60, tempF: 100)
    ])
    return ScheduleView()
        .environmentObject(SpaViewModel.preview())
        .environmentObject(store)
        .preferredColorScheme(.dark)
}
#endif
