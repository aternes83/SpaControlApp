import Foundation

struct SpaStatus: Decodable {
    var tempF:     Double
    var setpoint:  Double
    var heater:    Bool
    var pump1:     Int
    var pump2:     Bool
    var pump3:     Bool
    var light:     Bool
    var eco:       Bool
    var maxJet:    Bool?    // optional so status from older firmware still decodes
    var fault:     Bool
    var faultCode: Int
    var scheduleOn:     Bool?   // schedule feature enabled on the controller
    var scheduleActive: Bool?   // a heat window is currently active
    var fw:             String? // controller firmware version (for update checks)
}
