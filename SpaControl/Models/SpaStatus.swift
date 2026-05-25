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
    var fault:     Bool
    var faultCode: Int
}
