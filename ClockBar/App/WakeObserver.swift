import AppKit
import Foundation

@MainActor
final class WakeObserver {
    private let viewModel: StatusViewModel
    private let coordinator: PunchReminderCoordinator
    private var observers: [NSObjectProtocol] = []
    private var autoPunchInFlight = false

    /// The actions the on-wake catch-up may complete — the same ones the
    /// launchd auto-punch handles.
    private static let autoPunchActionsOnWake: [ClockAction] = [.clockin, .clockout]
    /// How early (before a window opens) still counts as "imminent" for pre-warming.
    private static let prewarmLeadMinutes = 10

    init(viewModel: StatusViewModel, coordinator: PunchReminderCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWake(reason: name.rawValue)
                }
            }
            observers.append(token)
        }
    }

    private func handleWake(reason: String) {
        // refresh() is fire-and-forget — the wake logic below fetches its own status.
        viewModel.refresh()
        Task { @MainActor [weak self] in
            await self?.maybePrewarmAndAutoPunch(reason: reason)
        }
    }

    /// On wake: pre-warm the 104 session if a scheduled punch is imminent, and —
    /// if the user opted in and we're inside the window — complete the punch
    /// ourselves. Always hands off to the reminder coordinator at the end.
    private func maybePrewarmAndAutoPunch(reason: String) async {
        guard !autoPunchInFlight else {
            Log.info("wake.autopunch", "skipped", ["reason": "in_flight"])
            return
        }
        autoPunchInFlight = true
        defer {
            autoPunchInFlight = false
            coordinator.checkPending(reason: reason)
        }

        let config = viewModel.config
        guard config.requiresScheduledJobs else { return }
        guard !FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) else { return }

        // Pure-clock check first: most wakes aren't near a punch window, so bail
        // before the holiday lookup or any 104 round-trip.
        let windowActions = Self.autoPunchActionsOnWake.filter {
            viewModel.punchWindowState(for: $0, leadMinutes: Self.prewarmLeadMinutes) == .inWindow
        }
        guard !windowActions.isEmpty else { return }

        if await HolidayStore.isHoliday() {
            Log.info("wake.autopunch", "skipped", ["reason": "holiday"])
            return
        }

        var status = await ClockService.getStatus()

        func isPending(_ action: ClockAction) -> Bool {
            // A status error is usually the unauthorized one — exactly what we
            // want to pre-warm for, so treat it as pending.
            if status.error != nil { return true }
            if action == .clockout, status.clockIn == nil { return false }
            return status.punchTime(for: action) == nil
        }
        guard windowActions.contains(where: isPending) else { return }

        let recovered = await viewModel.forceSessionRecovery(trigger: "wake_pre_punch")
        Log.info("wake.autopunch", "prewarmed", ["recovered": recovered ? "true" : "false"])

        // Complete the punch ourselves, if the user opted in.
        guard config.autoPunchOnWakeEnabled else {
            Log.info("wake.autopunch", "skipped", ["reason": "setting_disabled"])
            return
        }
        guard config.autopunchEnabled else {
            Log.info("wake.autopunch", "skipped", ["reason": "autopunch_disabled"])
            return
        }
        guard recovered else {
            Log.info("wake.autopunch", "skipped", ["reason": "auth_required"])
            return
        }

        // Re-fetch authoritative status now that cookies are fresh.
        status = await ClockService.getStatus()
        guard status.error == nil else {
            Log.info("wake.autopunch", "skipped", ["reason": "status_error"])
            return
        }

        // The flock is what actually prevents a double sendPunch: if the launchd
        // helper is mid-run it holds this and we bail (and vice versa).
        guard let lock = AutoPunchLock.tryAcquireExclusive() else {
            Log.info("wake.autopunch", "skipped", ["reason": "lock_busy"])
            return
        }
        defer { lock.release() }

        for action in Self.autoPunchActionsOnWake {
            if action == .clockout, status.clockIn == nil {
                Log.info("wake.autopunch", "skipped", ["reason": "no_clockin", "action": action.rawValue])
                continue
            }
            if status.punchTime(for: action) != nil {
                Log.info("wake.autopunch", "skipped", ["reason": "already_punched", "action": action.rawValue])
                continue
            }
            let grace =
                max(config.missedPunchNotificationDelay, autoPunchLatenessFloorSeconds)
                + config.schedule.delayMax(for: action)
            guard viewModel.punchWindowState(for: action, trailingGraceSeconds: grace) == .inWindow else {
                Log.info("wake.autopunch", "skipped", ["reason": "outside_window", "action": action.rawValue])
                continue
            }

            Log.info("wake.autopunch", "started", ["action": action.rawValue])
            let after = await ClockService.punch(component: "wake.autopunch")
            if after.error == nil, let punchedAt = after.punchTime(for: action) {
                Log.info(
                    "wake.autopunch", "completed",
                    [
                        "action": action.rawValue,
                        "punched_at": punchedAt,
                    ])
                NotificationManager.shared.send(
                    appName,
                    body: "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchedAt)"
                )
                status = after
            } else {
                Log.warn(
                    "wake.autopunch", "failed",
                    [
                        "action": action.rawValue,
                        "reason": after.error == nil ? "verification_pending" : "exception",
                        "error_message": after.error ?? "",
                    ])
            }
            viewModel.refresh()
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
        }
    }
}
