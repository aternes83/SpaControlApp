import Foundation

/// NTC thermistor calibration: presets, the 2-point Beta solver, and the
/// resistance→temperature conversion used for the wizard's live preview.
///
/// Model (matches the firmware's `NTCSensor`):
///     R = R0 · exp( Beta · (1/T − 1/T0) )        (T in Kelvin)
///  ⇔  1/T = 1/T0 + (1/Beta) · ln(R / R0)
enum TempCalibration {

    /// The fixed divider resistor installed in the hardware (3.3V ─ R_fixed ─ ADC ─ NTC ─ GND).
    /// Standard build value; exposed so an installer can override for a non-standard board.
    static let defaultRFixed: Double = 10_000

    // MARK: - Unit helpers

    static func fToK(_ f: Double) -> Double { (f - 32.0) / 1.8 + 273.15 }
    static func cToK(_ c: Double) -> Double { c + 273.15 }

    // MARK: - Resistance → temperature (live preview / sanity check)

    static func tempF(fromOhms r: Double, cal: TempCalDTO) -> Double? {
        guard r > 0, cal.r0 > 0, cal.beta != 0 else { return nil }
        let t0k = cToK(cal.t0C)
        let invT = 1.0 / t0k + (1.0 / cal.beta) * log(r / cal.r0)
        guard invT > 0 else { return nil }
        let tC = 1.0 / invT - 273.15
        return tC * 1.8 + 32.0 + cal.offsetF
    }

    // MARK: - 2-point solve

    /// Solve Beta and the 25 °C reference resistance from two (resistance, known-°F)
    /// points. Returns nil if the points are degenerate (same temperature / bad data).
    static func solve(r1: Double, tF1: Double,
                      r2: Double, tF2: Double,
                      rFixed: Double = defaultRFixed) -> TempCalDTO? {
        guard r1 > 0, r2 > 0, tF1.isFinite, tF2.isFinite else { return nil }
        let t1 = fToK(tF1)
        let t2 = fToK(tF2)
        let inv1 = 1.0 / t1
        let inv2 = 1.0 / t2
        guard abs(inv1 - inv2) > 1e-9, abs(r1 - r2) > 1e-6 else { return nil }

        let beta = log(r1 / r2) / (inv1 - inv2)
        guard beta.isFinite, beta > 0 else { return nil }

        // Normalise the reference to 25 °C: R0 = R1 · exp(−Beta·(1/T1 − 1/T0)).
        let t0c = 25.0
        let t0k = cToK(t0c)
        let r0 = r1 * exp(-beta * (inv1 - 1.0 / t0k))
        guard r0.isFinite, r0 > 0 else { return nil }

        return TempCalDTO(rFixed: rFixed, r0: r0, t0C: t0c, beta: beta, offsetF: 0)
    }

    /// Minimum temperature spread between the two calibration points for a
    /// trustworthy Beta fit. Too close and small reading errors blow up Beta.
    static let minSpreadF: Double = 15.0

    // MARK: - Presets

    struct Preset: Identifiable {
        let id: String
        let name: String
        let detail: String
        let cal: TempCalDTO
    }

    /// Common spa-pack NTC probes. Beta/R25 are the published nominal curves; the
    /// 2-point wizard still beats any preset for an unknown or aged sensor.
    static let presets: [Preset] = [
        Preset(id: "balboa10k",  name: "Balboa 10k",
               detail: "Balboa / most retrofit packs · 10kΩ @ 25°C",
               cal: TempCalDTO(rFixed: defaultRFixed, r0: 10_000, t0C: 25, beta: 3950, offsetF: 0)),
        Preset(id: "gecko10k",   name: "Gecko / Aeware 10k",
               detail: "Gecko in.xe / in.ye packs · 10kΩ @ 25°C",
               cal: TempCalDTO(rFixed: defaultRFixed, r0: 10_000, t0C: 25, beta: 3970, offsetF: 0)),
        Preset(id: "generic3950", name: "Generic 10k (β3950)",
               detail: "Common waterproof 10kΩ NTC probe",
               cal: TempCalDTO(rFixed: defaultRFixed, r0: 10_000, t0C: 25, beta: 3950, offsetF: 0)),
        Preset(id: "generic3435", name: "Generic 10k (β3435)",
               detail: "10kΩ NTC, β3435 variant",
               cal: TempCalDTO(rFixed: defaultRFixed, r0: 10_000, t0C: 25, beta: 3435, offsetF: 0)),
    ]
}

// MARK: - Saved profiles

/// A named calibration the user has created/applied, persisted so a fleet
/// installer can reuse the same curve across spas.
struct CalProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var cal: TempCalDTO
    var createdAt: Date = Date()
}

/// Persists calibration profiles to UserDefaults as JSON.
final class CalProfileStore: ObservableObject {
    @Published private(set) var profiles: [CalProfile] = []

    private let key = "spa.tempCalProfiles"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ profile: CalProfile) {
        profiles.insert(profile, at: 0)
        save()
    }

    func delete(_ profile: CalProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CalProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
