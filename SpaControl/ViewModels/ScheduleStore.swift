import Foundation
import Combine

/// Holds the user's spa schedule, persists it locally, and hands out the wire
/// DTO for pushing to the controller. The controller keeps its own copy
/// (`schedule.json`) and enforces it autonomously, so the schedule keeps running
/// even when the phone is away — this store is the editing/display source of
/// truth on the app side.
final class ScheduleStore: ObservableObject {
    @Published var schedule: Schedule {
        didSet { persist() }
    }

    private let key = "spa.schedule.v1"

    init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "seedSchedule") {
            schedule = Schedule(enabled: true, offTempF: 80, windows: [
                ScheduleWindow(enabled: true, days: Set(0...4),
                               startMinutes: 21*60, endMinutes: 6*60, tempF: 102),
                ScheduleWindow(enabled: false, days: [5, 6],
                               startMinutes: 8*60, endMinutes: 11*60, tempF: 100)
            ])
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Schedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = Schedule()
        }
    }

    var dto: ScheduleDTO { ScheduleDTO(schedule) }

    // MARK: Mutations

    func addWindow() {
        schedule.windows.append(ScheduleWindow())
    }

    func update(_ window: ScheduleWindow) {
        guard let i = schedule.windows.firstIndex(where: { $0.id == window.id }) else { return }
        schedule.windows[i] = window
    }

    func delete(at offsets: IndexSet) {
        schedule.windows.remove(atOffsets: offsets)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
