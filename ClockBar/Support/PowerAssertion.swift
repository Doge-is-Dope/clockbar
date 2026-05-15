import Foundation
import IOKit.pwr_mgt

/// RAII wrapper around an IOKit power assertion. Blocks idle-timer sleep
/// while held; does not block lid-close sleep on battery without an
/// external display. Released on `deinit`; the kernel reclaims it on
/// process death.
final class PowerAssertion {
    private var id: IOPMAssertionID

    private init(id: IOPMAssertionID) { self.id = id }

    deinit { release() }

    static func preventIdleSleep(reason: String) -> PowerAssertion? {
        var id: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return nil }
        return PowerAssertion(id: id)
    }

    func release() {
        if id != IOPMAssertionID(0) {
            IOPMAssertionRelease(id)
            id = IOPMAssertionID(0)
        }
    }
}
