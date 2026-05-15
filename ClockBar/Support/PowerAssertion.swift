import Foundation
import IOKit.pwr_mgt

/// RAII wrapper around an IOKit power assertion. Holding an instance prevents
/// idle system sleep so a network round-trip can complete without macOS
/// suspending the process mid-flight. The assertion releases on `release()` or
/// `deinit`, and the kernel reclaims it on process death — a crashed helper
/// will not leak the assertion.
///
/// `kIOPMAssertPreventUserIdleSystemSleep` blocks idle-timer sleep on AC and
/// battery alike. It does NOT prevent user-initiated sleep (lid close on a
/// MacBook without an external display, or `pmset sleepnow`).
final class PowerAssertion {
    private var id: IOPMAssertionID

    private init(id: IOPMAssertionID) { self.id = id }

    deinit { release() }

    /// Acquire an assertion that prevents idle system sleep. Returns nil if
    /// IOKit refuses to issue one (rare; logged by the caller).
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
