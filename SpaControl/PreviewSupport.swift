#if DEBUG
import Foundation

// Sample data so Xcode canvas previews render populated (not the disconnected
// empty state). Compiled only in DEBUG builds.

extension SpaStatus {
    static func sample(
        tempF: Double = 98, setpoint: Double = 102, heater: Bool = true,
        pump1: Int = 1, pump2: Bool = false, pump3: Bool = false,
        light: Bool = false, eco: Bool = false, fault: Bool = false, faultCode: Int = 0
    ) -> SpaStatus {
        SpaStatus(tempF: tempF, setpoint: setpoint, heater: heater, pump1: pump1,
                  pump2: pump2, pump3: pump3, light: light, eco: eco,
                  fault: fault, faultCode: faultCode)
    }
}

extension SpaViewModel {
    /// A connected view model with sample data, for previews only.
    static func preview(_ status: SpaStatus = .sample()) -> SpaViewModel {
        let vm = SpaViewModel()
        vm.status = status
        vm.connectionState = .connected
        return vm
    }
}
#endif
