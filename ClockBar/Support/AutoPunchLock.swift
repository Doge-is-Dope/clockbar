import Darwin
import Foundation

@_silgen_name("flock")
private func c_flock(_ fd: Int32, _ operation: Int32) -> Int32

/// Global advisory lock coordinating `AutoPunchEngine.run` with
/// `LaunchAgentManager`'s bootout/bootstrap paths. Prevents
/// `launchctl bootout` from killing an in-flight helper mid-punch.
///
/// Kernel-released on any process death (including SIGKILL), so no
/// signal handling is needed. Assumes `~/.104` is on APFS $HOME —
/// flock semantics may differ on network filesystems or iCloud Drive.
final class AutoPunchLock {
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    deinit { release() }

    static func tryAcquireExclusive() -> AutoPunchLock? {
        let fd = Darwin.open(autoPunchLockPath.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        if c_flock(fd, LOCK_EX | LOCK_NB) != 0 {
            Darwin.close(fd)
            return nil
        }
        return AutoPunchLock(fd: fd)
    }

    /// Polls `tryAcquireExclusive` every 250ms up to `timeout` seconds.
    /// Returns the held lock on success (caller owns release), nil on timeout.
    static func waitAndAcquire(timeout: TimeInterval) -> AutoPunchLock? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let lock = tryAcquireExclusive() { return lock }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    func release() {
        if fd >= 0 {
            _ = c_flock(fd, LOCK_UN)
            Darwin.close(fd)
            fd = -1
        }
    }
}
