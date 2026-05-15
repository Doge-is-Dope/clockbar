import Foundation

enum AutoPunchEngine {
    static func run(action: ClockAction, dryRun: Bool = false) async -> Int32 {
        let component = "auto.\(action.rawValue)"
        let argv = CommandLine.arguments.dropFirst().joined(separator: " ")
        Log.info(
            component, "invoked",
            [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "dry_run": dryRun,
                "argv": argv,
            ])

        guard let lock = AutoPunchLock.tryAcquireExclusive() else {
            Log.info(component, "lock_busy")
            return 0
        }
        defer { lock.release() }

        // Keep the system awake for the whole attempt so we can't idle-sleep
        // mid-recovery and miss the punch window.
        let powerAssertion = PowerAssertion.preventIdleSleep(reason: "ClockBar auto-punch in progress")
        if powerAssertion == nil {
            Log.warn(component, "power_assertion_unavailable")
        }
        defer { powerAssertion?.release() }

        let config = ConfigManager.load()

        if FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path)
            || (!config.autopunchEnabled && !config.missedPunchNotificationEnabled)
        {
            Log.info(component, "skipped", ["reason": "disabled"])
            return 0
        }

        let notificationOnly = !config.autopunchEnabled

        if await HolidayStore.isHoliday() {
            Log.info(component, "skipped", ["reason": "holiday"])
            return 0
        }

        guard let schedule = ScheduledTime(string: config.schedule.time(for: action)) else {
            Log.error(component, "failed", ["reason": "invalid_schedule"])
            notify(
                title: "\(appName) - Failed",
                body: "Invalid \(action.displayName) schedule.",
                sound: notificationErrorSound,
                dryRun: dryRun
            )
            return 1
        }

        let now = Date()
        let scheduledDate = schedule.date(on: now)
        if notificationOnly {
            await notifyMissedPunchAfterThresholdIfNeeded(
                action: action,
                schedule: schedule,
                scheduledDate: scheduledDate,
                threshold: config.notificationDelaySeconds,
                dryRun: dryRun
            )
            return 0
        }

        let plan = Self.computeDelayPlan(for: action, config: config)
        let targetText = plan.target?.displayString ?? "(\(plan.delay)s from now)"
        Log.info(
            component, "sleeping",
            [
                "delay_s": plan.delay,
                "target": targetText,
                "source": plan.source.rawValue,
            ])
        if dryRun {
            print("[dry-run] Would sleep \(plan.delay)s (\(plan.delay / 60)m\(plan.delay % 60)s)")
        } else if plan.delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(plan.delay) * 1_000_000_000)
        }

        // If launchd misfired this job long after the schedule (e.g. Mac woke from
        // sleep well past target), don't auto-punch — let the app's reminder
        // coordinator drive a Late or Missed notification instead.
        if !dryRun {
            let secondsLate = Int(Date().timeIntervalSince(scheduledDate))
            let grace = config.lateGraceSeconds(for: action)
            if secondsLate > grace {
                Log.info(
                    component, "skipped",
                    [
                        "reason": "past_grace_at_helper_run",
                        "seconds_late": secondsLate,
                        "grace_s": grace,
                    ])
                if config.missedPunchNotificationEnabled {
                    await notifyMissedPunchAfterThresholdIfNeeded(
                        action: action,
                        schedule: schedule,
                        scheduledDate: scheduledDate,
                        threshold: 0,
                        dryRun: dryRun
                    )
                }
                return 0
            }
        }

        var session: StoredSession
        if let existing = AuthStore.loadSession(), existing.hasUsableCookies {
            session = existing
        } else {
            let result = await awaitRefreshedSession(component: component, trigger: "missing_session")
            if let recovered = result.session {
                Log.info(component, "session_refresh_recovered", ["waited_s": result.waitedSeconds])
                session = recovered
            } else {
                Log.info(component, "session_refresh_timeout", ["waited_s": result.waitedSeconds])
                Log.error(component, "failed", ["reason": "missing_session"])
                if !config.missedPunchNotificationEnabled {
                    notify(
                        title: "\(appName) - Login Required",
                        body: "Open ClockBar and sign in to 104 again.",
                        sound: notificationErrorSound,
                        dryRun: dryRun
                    )
                } else {
                    await notifyMissedPunchAfterThresholdIfNeeded(
                        action: action,
                        schedule: schedule,
                        scheduledDate: scheduledDate,
                        threshold: config.notificationDelaySeconds,
                        dryRun: dryRun
                    )
                }
                return 1
            }
        }

        // One getStatus → sendPunch → verify attempt; on `.unauthorized` request a
        // silent session refresh and retry once. The flock (held by `run`) keeps
        // this from racing the app's on-wake catch-up.
        var didRefresh = false
        while true {
            switch await attemptPunch(
                session: session,
                action: action,
                config: config,
                component: component,
                dryRun: dryRun,
                schedule: schedule,
                scheduledDate: scheduledDate
            ) {
            case .completed:
                return 0
            case .verificationPending, .failed:
                return 1
            case .unauthorized(let step):
                Log.error(
                    component, "failed",
                    ["reason": didRefresh ? "unauthorized_after_refresh" : "unauthorized", "step": step])
                if dryRun || didRefresh {
                    await unauthorizedFallout(
                        action: action,
                        config: config,
                        schedule: schedule,
                        scheduledDate: scheduledDate,
                        dryRun: dryRun
                    )
                    return 1
                }
                let refresh = await awaitRefreshedSession(component: component, trigger: "unauthorized")
                guard let refreshed = refresh.session else {
                    Log.info(
                        component, "session_refresh_timeout",
                        ["after": "unauthorized", "waited_s": refresh.waitedSeconds])
                    await unauthorizedFallout(
                        action: action,
                        config: config,
                        schedule: schedule,
                        scheduledDate: scheduledDate,
                        dryRun: false
                    )
                    return 1
                }
                Log.info(
                    component, "session_refresh_recovered",
                    ["after": "unauthorized", "waited_s": refresh.waitedSeconds])
                session = refreshed
                didRefresh = true
            }
        }
    }

    /// Outcome of one getStatus → sendPunch → verifyStatus attempt. `.completed`
    /// covers every path `run` would exit 0 on. On `.unauthorized` the caller
    /// retries after a session refresh — `attemptPunch` doesn't notify or post
    /// `SessionRefreshSignal` itself on that path.
    private enum PunchAttemptOutcome {
        case completed
        case verificationPending
        case unauthorized(step: String)
        case failed
    }

    private static func attemptPunch(
        session: StoredSession,
        action: ClockAction,
        config: ClockConfig,
        component: String,
        dryRun: Bool,
        schedule: ScheduledTime,
        scheduledDate: Date
    ) async -> PunchAttemptOutcome {
        var session = session
        var currentStep = "getStatus"
        do {
            Log.info(component, "step", ["name": "getStatus"])
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)

            if action == .clockout, status.clockIn == nil {
                let message = "Cannot clock out because there is no clock-in record yet."
                Log.info(component, "skipped", ["reason": "no_clockin"])
                notify(title: appName, body: message, dryRun: dryRun)
                if config.missedPunchNotificationEnabled {
                    await notifyMissedPunchAfterThresholdIfNeeded(
                        action: action,
                        schedule: schedule,
                        scheduledDate: scheduledDate,
                        threshold: config.notificationDelaySeconds,
                        dryRun: dryRun
                    )
                }
                return .completed
            }

            if let existingPunchTime = status.punchTime(for: action) {
                Log.info(
                    component, "already_punched",
                    [
                        "action": action.rawValue,
                        "punched_at": existingPunchTime,
                    ])
                return .completed
            }

            if dryRun {
                let statusData = try? JSONEncoder.clockStore.encode(status)
                if let statusData {
                    print("[dry-run] Would punch (\(action.rawValue))")
                    print("[dry-run] Current status: \(String(decoding: statusData, as: UTF8.self))")
                }
                Log.info(component, "completed", ["dry_run": true])
                return .completed
            }

            currentStep = "sendPunch"
            Log.info(component, "step", ["name": "sendPunch"])
            try await Clock104API.sendPunch(session: session)
            currentStep = "verifyStatus"
            Log.info(component, "step", ["name": "verifyStatus"])
            let verified = try await Clock104API.getStatus(session: session)
            if let punchTime = verified.punchTime(for: action) {
                let message = "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchTime)"
                if action == .clockout, let clockIn = verified.clockIn {
                    Log.info(
                        component, "completed",
                        [
                            "action": action.rawValue,
                            "punched_at": punchTime,
                            "previous_in": clockIn,
                        ])
                } else {
                    Log.info(
                        component, "completed",
                        [
                            "action": action.rawValue,
                            "punched_at": punchTime,
                        ])
                }
                notify(title: appName, body: message, dryRun: dryRun)
                return .completed
            }

            Log.warn(component, "verification_pending")
            notify(
                title: "\(appName) - Warning",
                body: "Punch sent but not verified.",
                sound: notificationErrorSound,
                dryRun: dryRun
            )
            if config.missedPunchNotificationEnabled {
                await notifyMissedPunchAfterThresholdIfNeeded(
                    action: action,
                    schedule: schedule,
                    scheduledDate: scheduledDate,
                    threshold: config.notificationDelaySeconds,
                    dryRun: dryRun
                )
            }
            return .verificationPending
        } catch Clock104Error.unauthorized {
            return .unauthorized(step: currentStep)
        } catch {
            Log.error(
                component, "failed",
                [
                    "reason": "exception",
                    "error_message": error.localizedDescription,
                    "step": currentStep,
                ])
            notify(
                title: "\(appName) - Failed",
                body: error.localizedDescription,
                sound: notificationErrorSound,
                dryRun: dryRun
            )
            if config.missedPunchNotificationEnabled {
                await notifyMissedPunchAfterThresholdIfNeeded(
                    action: action,
                    schedule: schedule,
                    scheduledDate: scheduledDate,
                    threshold: config.notificationDelaySeconds,
                    dryRun: dryRun
                )
            }
            return .failed
        }
    }

    /// Asks the app to refresh the session and waits up to 60s for cookies
    /// to change on disk. `waitedSeconds` much larger than the budget means
    /// the helper was suspended through sleep.
    private static func awaitRefreshedSession(component: String, trigger: String) async -> (
        session: StoredSession?, waitedSeconds: Int
    ) {
        let baseline = AuthStore.loadSession()
        let baselineValidatedAt = baseline?.lastValidatedAt ?? .distantPast
        let baselineHeader = baseline?.cookieHeader
        Log.info(
            component, "session_refresh_requested",
            [
                "trigger": trigger,
                "timeout_s": Int(sessionRefreshTimeoutSeconds),
            ])
        SessionRefreshSignal.post()
        let started = Date()
        let deadline = started.addingTimeInterval(sessionRefreshTimeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: sessionRefreshPollIntervalNanos)
            guard let session = AuthStore.loadSession(), session.hasUsableCookies else { continue }
            let changed =
                (session.lastValidatedAt ?? .distantPast) > baselineValidatedAt
                || session.cookieHeader != baselineHeader
            if changed { return (session, Int(Date().timeIntervalSince(started))) }
        }
        return (nil, Int(Date().timeIntervalSince(started)))
    }

    private static func unauthorizedFallout(
        action: ClockAction,
        config: ClockConfig,
        schedule: ScheduledTime,
        scheduledDate: Date,
        dryRun: Bool
    ) async {
        if !config.missedPunchNotificationEnabled {
            notify(
                title: "\(appName) - Login Required",
                body: Clock104Error.unauthorized.localizedDescription,
                sound: notificationErrorSound,
                dryRun: dryRun
            )
        } else {
            await notifyMissedPunchAfterThresholdIfNeeded(
                action: action,
                schedule: schedule,
                scheduledDate: scheduledDate,
                threshold: config.notificationDelaySeconds,
                dryRun: dryRun
            )
        }
    }

    private static func notifyMissedPunchAfterThresholdIfNeeded(
        action: ClockAction,
        schedule: ScheduledTime,
        scheduledDate: Date,
        threshold: Int,
        dryRun: Bool
    ) async {
        let component = "notification.\(action.rawValue)"
        let remainingDelay = max(0, threshold - Int(Date().timeIntervalSince(scheduledDate)))

        if dryRun {
            print("[dry-run] Would wait \(remainingDelay)s before checking missed \(action.logLabel)")
        } else if remainingDelay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remainingDelay) * 1_000_000_000)
            } catch {
                Log.info(component, "cancelled", ["during": "missed_punch_delay"])
                return
            }
        }

        let status = await currentStatusForMissedPunchCheck()
        if let status, status.punchTime(for: action) != nil {
            Log.info(component, "skipped", ["reason": "already_punched"])
            return
        }

        let body = "Scheduled \(action.logLabel) at \(schedule.displayString) has passed."

        Log.warn(component, "missed_punch")
        notify(title: appName, body: body, kind: .missedPunch(action), dryRun: dryRun)
    }

    private static let sessionRefreshTimeoutSeconds: TimeInterval = 60
    private static let sessionRefreshPollIntervalNanos: UInt64 = 500_000_000

    private enum DelaySource: String {
        case nextPunchStore = "NextPunchStore"
        case fallbackRandom = "fallback-random"
    }

    private struct DelayPlan {
        let delay: Int
        let target: ScheduledTime?
        let source: DelaySource
    }

    private static func computeDelayPlan(for action: ClockAction, config: ClockConfig) -> DelayPlan {
        let today = DateFormatter.statusDate.string(from: Date())

        if let punch = NextPunchStore.load(), punch.date == today {
            let targetTime = action == .clockin ? punch.clockin : punch.clockout
            if let target = ScheduledTime(string: targetTime) {
                let now = Date()
                let targetDate = target.date(on: now)
                return DelayPlan(
                    delay: max(0, Int(targetDate.timeIntervalSince(now))),
                    target: target,
                    source: .nextPunchStore
                )
            }
        }

        let delay = Int.random(in: 0...max(config.schedule.delayMax(for: action), 0))
        return DelayPlan(delay: delay, target: nil, source: .fallbackRandom)
    }

    private static func currentStatusForMissedPunchCheck() async -> PunchStatus? {
        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            return nil
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)
            return status
        } catch {
            return nil
        }
    }

    private enum NotificationKind {
        case plain
        case missedPunch(ClockAction)
    }

    private static func notify(
        title: String,
        body: String,
        sound: String = "default",
        kind: NotificationKind = .plain,
        dryRun: Bool
    ) {
        guard !dryRun else {
            print("[dry-run] Would notify \"\(title)\": \(body)")
            return
        }

        switch kind {
        case .plain:
            SystemUI.notify(title: title, body: body, sound: sound)
        case .missedPunch(let action):
            SystemUI.notifyMissedPunch(action: action, title: title, body: body)
        }
    }
}
