import Foundation

/// The alert types the app can raise. Each maps to a user-toggleable preference
/// (all default ON) and carries its own copy/icon for the settings screen.
enum NotificationCategory: String, CaseIterable, Identifiable {
    case reachedTarget
    case freeze
    case fault
    case highTemp
    case lowTemp
    case sensorFault
    case offline
    case updateAvailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reachedTarget:   return "Reached target temperature"
        case .freeze:          return "Freeze protection"
        case .fault:           return "Faults"
        case .highTemp:        return "High-temperature alarm"
        case .lowTemp:         return "Low-temperature alarm"
        case .sensorFault:     return "Water-sensor fault"
        case .offline:         return "Spa offline"
        case .updateAvailable: return "Software updates"
        }
    }

    var detail: String {
        switch self {
        case .reachedTarget:   return "When the water reaches your set temperature."
        case .freeze:          return "When freezing conditions engage freeze protection."
        case .fault:           return "No-flow and emergency-stop faults."
        case .highTemp:        return "Over-temperature and high-limit trips."
        case .lowTemp:         return "When the heater can't raise the temperature."
        case .sensorFault:     return "When the water temperature sensor reads out of range."
        case .offline:         return "When the spa stops reporting for 30 minutes."
        case .updateAvailable: return "When new app or controller firmware is available."
        }
    }

    var icon: String {
        switch self {
        case .reachedTarget:   return "checkmark.circle.fill"
        case .freeze:          return "snowflake"
        case .fault:           return "exclamationmark.triangle.fill"
        case .highTemp:        return "thermometer.sun.fill"
        case .lowTemp:         return "thermometer.snowflake"
        case .sensorFault:     return "sensor.tag.radiowaves.forward.fill"
        case .offline:         return "wifi.slash"
        case .updateAvailable: return "arrow.down.circle.fill"
        }
    }
}

/// UserDefaults-backed on/off state for each alert category. Absent key = ON.
enum NotificationSettings {
    private static func key(_ c: NotificationCategory) -> String { "notif.\(c.rawValue)" }

    static func isEnabled(_ c: NotificationCategory) -> Bool {
        UserDefaults.standard.object(forKey: key(c)) as? Bool ?? true
    }

    static func setEnabled(_ c: NotificationCategory, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key(c))
    }
}
