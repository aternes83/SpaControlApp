import Foundation

/// Where the monitor sends its decisions. `NotificationManager` is the live
/// implementation; tests substitute a recording sink.
protocol SpaAlertSink: AnyObject {
    func reachedTarget(temp: Int)
    func freeze()
    func fault(code: Int)
    func highTemp(code: Int)
    func sensorFault(temp: Int)
    func lowTemp()
    func faultCleared()
    func rearmOffline()
}

/// Watches the incoming status stream and raises notifications on the edges that
/// matter. All conditions are derived from the fields the controller already
/// publishes (temp / setpoint / heater / fault), so no extra firmware is needed
/// and everything is testable by injecting status messages.
///
/// State is edge-triggered and re-baselined on `reset()` (called when the
/// connection drops) so reconnecting never replays old alerts.
final class SpaAlertMonitor {

    private let sink: SpaAlertSink
    private let now: () -> Date

    /// `sink` defaults to the live notifier; `now` is injectable so the 30-minute
    /// stall timer can be tested deterministically.
    init(sink: SpaAlertSink = NotificationManager.shared, now: @escaping () -> Date = { Date() }) {
        self.sink = sink
        self.now = now
    }

    // Thresholds
    private let freezeOnF: Double  = 40      // ≤ → freeze protection engaged
    private let freezeOffF: Double = 45      // ≥ → clear (hysteresis)
    private let sensorMinF: Double = 20      // outside [min,max] → sensor fault
    private let sensorMaxF: Double = 130
    private let stallSeconds: TimeInterval = 30 * 60
    private let stallRiseF: Double = 1.0     // required rise to count as progress

    // Edge state
    private var wasBelowSetpoint: Bool?      // nil = not yet baselined
    private var lastFaultCode: Int?          // nil = not yet baselined
    private var inFreeze = false
    private var sensorFaulted = false
    private var stallAnchor: (date: Date, temp: Double)?
    private var stallNotified = false

    func reset() {
        wasBelowSetpoint = nil
        lastFaultCode = nil
        inFreeze = false
        sensorFaulted = false
        stallAnchor = nil
        stallNotified = false
    }

    /// Process one freshly received status. Call on the main thread.
    func process(_ s: SpaStatus) {
        // Any valid report pushes the 30-minute offline alarm back out.
        sink.rearmOffline()

        let temp = s.tempF
        let sensorOK = temp >= sensorMinF && temp <= sensorMaxF

        handleSensor(temp: temp, ok: sensorOK)
        handleFaultCode(s)

        // Temperature-derived alerts are meaningless while the sensor is bad.
        guard sensorOK else { return }
        handleReachedTarget(temp: temp, setpoint: s.setpoint)
        handleFreeze(temp: temp)
        handleHeatStall(temp: temp, setpoint: s.setpoint, heating: s.heater)
    }

    // MARK: Water-sensor plausibility

    private func handleSensor(temp: Double, ok: Bool) {
        if !ok {
            if !sensorFaulted { sink.sensorFault(temp: Int(temp.rounded())); sensorFaulted = true }
        } else if sensorFaulted {
            sensorFaulted = false
        }
    }

    // MARK: Faults (routed: temperature trips vs. generic vs. cleared)

    private func handleFaultCode(_ s: SpaStatus) {
        let code = s.fault ? s.faultCode : 0
        guard let previous = lastFaultCode else { lastFaultCode = code; return }  // baseline
        guard code != previous else { return }
        lastFaultCode = code
        switch code {
        case 0:       sink.faultCleared()
        case 2, 3:    sink.highTemp(code: code)   // high-limit / over-temp
        default:      sink.fault(code: code)      // no-flow / e-stop / other
        }
    }

    // MARK: Reached target

    private func handleReachedTarget(temp: Double, setpoint: Double) {
        let below = temp < setpoint - 0.5
        let reached = temp >= setpoint - 0.05
        guard let wasBelow = wasBelowSetpoint else { wasBelowSetpoint = below; return }  // baseline
        if reached && wasBelow {
            sink.reachedTarget(temp: Int(setpoint.rounded()))
            wasBelowSetpoint = false
        } else if below {
            wasBelowSetpoint = true
        }
    }

    // MARK: Freeze protection

    private func handleFreeze(temp: Double) {
        if temp <= freezeOnF {
            if !inFreeze { sink.freeze(); inFreeze = true }
        } else if temp >= freezeOffF {
            inFreeze = false
        }
    }

    // MARK: Low-temp / heating stall (heating 30 min with < 1°F rise)

    private func handleHeatStall(temp: Double, setpoint: Double, heating: Bool) {
        guard heating && temp < setpoint else {
            stallAnchor = nil
            stallNotified = false
            return
        }
        guard let anchor = stallAnchor else {
            stallAnchor = (now(), temp)
            return
        }
        if temp >= anchor.temp + stallRiseF {
            stallAnchor = (now(), temp)           // progress — restart the clock
            stallNotified = false
        } else if !stallNotified,
                  now().timeIntervalSince(anchor.date) >= stallSeconds {
            sink.lowTemp()
            stallNotified = true
        }
    }
}
