import Foundation

/// One point in the temperature-history series, captured from an incoming
/// `spa/status`. Kept in-memory as a rolling window by SpaViewModel.
struct TempSample: Identifiable {
    let id = UUID()
    let date: Date
    let tempF: Double
    let setpoint: Double
}
