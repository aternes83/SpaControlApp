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
}
