import Foundation

/// A single recurring heat window. On the days it covers, the spa heats to
/// `tempF` between `startMinutes` and `endMinutes` (minutes after local
/// midnight). If `endMinutes <= startMinutes` the window wraps past midnight
/// (e.g. 9:00 PM → 6:00 AM off-peak overnight).
struct ScheduleWindow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var enabled: Bool = true
    /// Weekday indices this window runs on. 0 = Monday … 6 = Sunday, matching
    /// the controller's `machine.RTC()` weekday convention.
    var days: Set<Int> = Set(0...6)
    var startMinutes: Int = 21 * 60   // 9:00 PM
    var endMinutes: Int = 6 * 60      // 6:00 AM (wraps overnight)
    var tempF: Int = 102

    /// True when the window crosses midnight.
    var wrapsMidnight: Bool { endMinutes <= startMinutes }
}

/// The full spa schedule. While `enabled`, the controller heats to the active
/// window's target during covered hours and holds at `offTempF` the rest of the
/// time — the core Time-of-Day use case (heat only during off-peak hours).
struct Schedule: Codable, Equatable {
    var enabled: Bool = false
    /// Hold temperature outside every active window (peak-hour / away setpoint).
    var offTempF: Int = 80
    var windows: [ScheduleWindow] = []

    static let tempRange = 60...104
    static let offTempRange = 60...104
}

// MARK: - Time helpers

enum ScheduleTime {
    /// "9:00 PM" style label for minutes-after-midnight.
    static func label(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        var comps = DateComponents()
        comps.hour = m / 60
        comps.minute = m % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int) -> Date {
        var c = DateComponents()
        c.hour = (minutes / 60) % 24
        c.minute = minutes % 60
        return Calendar.current.date(from: c) ?? Date()
    }
}

// MARK: - Weekday labels (Mon…Sun, RTC order)

enum ScheduleWeekday {
    /// Single-letter labels in RTC order (index 0 = Monday … 6 = Sunday).
    static let short = ["M", "T", "W", "T", "F", "S", "S"]
    static let full  = ["Monday", "Tuesday", "Wednesday", "Thursday",
                        "Friday", "Saturday", "Sunday"]

    /// Compact summary of a day set, e.g. "Every day", "Weekdays",
    /// "Weekends", or "Mon, Wed, Fri".
    static func summary(_ days: Set<Int>) -> String {
        if days.isEmpty { return "No days" }
        if days == Set(0...6) { return "Every day" }
        if days == Set(0...4) { return "Weekdays" }
        if days == Set([5, 6]) { return "Weekends" }
        let abbr = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return days.sorted().map { abbr[$0] }.joined(separator: ", ")
    }
}

// MARK: - Wire format (app → controller)

/// Payload sent to the controller inside `SpaCommand.schedule`. The outer
/// `SpaCommand` encoder applies `.convertToSnakeCase`, so `offTempF` → `off_temp_f`
/// and `tempF` → `temp_f` on the wire.
struct ScheduleDTO: Encodable, Equatable {
    let enabled: Bool
    let offTempF: Int
    let windows: [Window]

    struct Window: Encodable, Equatable {
        let enabled: Bool
        let days: [Int]
        let start: Int
        let end: Int
        let tempF: Int
    }

    init(_ s: Schedule) {
        enabled = s.enabled
        offTempF = s.offTempF
        windows = s.windows.map {
            Window(enabled: $0.enabled,
                   days: $0.days.sorted(),
                   start: $0.startMinutes,
                   end: $0.endMinutes,
                   tempF: $0.tempF)
        }
    }
}
