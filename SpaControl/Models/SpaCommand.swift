import Foundation

/// Any field left nil is omitted from the JSON payload (Swift's synthesised
/// Encodable uses encodeIfPresent for Optional properties).
struct SpaCommand: Encodable {
    var setTemp: Double?
    var pump1:   Int?
    var pump2:   Bool?
    var pump3:   Bool?
    var light:   Bool?
    var eco:     Bool?
    var maxJet:  Bool?
    var schedule: ScheduleDTO?
    var setTempCal: TempCalDTO?
}

/// NTC temperature-sensor calibration pushed to the controller. The firmware
/// applies these Beta-model coefficients live and persists them to config.json,
/// so the spa keeps its calibration across reboots and runs standalone.
///
/// Explicit CodingKeys pin the exact wire names the firmware expects; the global
/// `.convertToSnakeCase` strategy leaves these already-snake keys unchanged.
struct TempCalDTO: Codable, Equatable {
    var rFixed:  Double   // divider fixed resistor (Ω)
    var r0:      Double   // reference resistance at t0 (Ω)
    var t0C:     Double   // reference temperature (°C)
    var beta:    Double   // NTC Beta constant (K)
    var offsetF: Double   // final trim offset (°F)

    enum CodingKeys: String, CodingKey {
        case rFixed  = "r_fixed"
        case r0      = "r0"
        case t0C     = "t0_c"
        case beta    = "beta"
        case offsetF = "offset_f"
    }
}
