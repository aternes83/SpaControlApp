import Foundation

/// Human-readable mapping for the board's `fault_code` field.
/// Mirrors `i_fault_code` in the firmware (spa_control.py):
/// 0=none, 1=no flow, 2=high limit, 3=overtemp, 4=e-stop.
enum FaultCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "No fault"
        case 1: return "No water flow detected"
        case 2: return "High-limit temperature cutoff tripped"
        case 3: return "Water over-temperature"
        case 4: return "Emergency stop engaged"
        default: return "Unknown fault (code \(code))"
        }
    }

    /// Short label for compact UI (e.g. the fault banner heading).
    static func shortLabel(_ code: Int) -> String {
        switch code {
        case 1: return "No Flow"
        case 2: return "High Limit"
        case 3: return "Over-Temp"
        case 4: return "E-Stop"
        default: return "Code \(code)"
        }
    }
}
