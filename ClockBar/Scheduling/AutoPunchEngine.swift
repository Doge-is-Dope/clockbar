import Foundation

let autoPunchLatenessFloorSeconds = 300

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
        let calendar = Calendar(identifier: .gregorian)
        let scheduledDate =
            calendar.date(
                bySettingHour: schedule.hour,
                minute: schedule.minute,
                second: 0,
                of: now
            ) ?? now
        if notificationOnly {
            await notifyMissedPunchAfterThresholdIfNeeded(
                action: action,
                schedule: schedule,
                scheduledDate: scheduledDate,
                threshold: max(0, config.missedPunchNotificationDelay),
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
        // coordinator drive a Late or Missed notification instead. The grace
        // accounts for the randomization window (`delayMax`) the helper
        // legitimately slept toward, plus a 5-minute floor for launchd jitter.
        if !dryRun {
            let secondsLate = Int(Date().timeIntervalSince(scheduledDate))
            let delayMax = config.schedule.delayMax(for: action)
            let grace = max(config.missedPunchNotificationDelay, autoPunchLatenessFloorSeconds) + delayMax
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
        } else if let recovered = await awaitFreshSession(
            baseline: nil,
            timeout: sessionRefreshTimeoutSeconds,
            component: component
        ) {
            session = recovered
        } else {
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
                    threshold: max(0, config.missedPunchNotificationDelay),
                    dryRun: dryRun
                )
            }
            return 1
        }

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
                        threshold: max(0, config.missedPunchNotificationDelay),
                        dryRun: dryRun
                    )
                }
                return 0
            }

            if let existingPunchTime = status.punchTime(for: action) {
                Log.info(
                    component, "already_punched",
                    [
                        "action": action.rawValue,
                        "punched_at": existingPunchTime,
                    ])
                return 0
            }

            if dryRun {
                let statusData = try? JSONEncoder.clockStore.encode(status)
                if let statusData {
                    print("[dry-run] Would punch (\(action.rawValue))")
                    print("[dry-run] Current status: \(String(decoding: statusData, as: UTF8.self))")
                }
                Log.info(component, "completed", ["dry_run": true])
                return 0
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
                return 0
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
                    threshold: max(0, config.missedPunchNotificationDelay),
                    dryRun: dryRun
                )
            }
            return 1
        } catch Clock104Error.unauthorized {
            Log.error(
                component, "failed",
                [
                    "reason": "unauthorized",
                    "step": currentStep,
                ])
            if !dryRun {
                SessionRefreshSignal.post()
                Log.info(component, "session_refresh_requested", ["trigger": "unauthorized"])
            }
            if !config.missedPunchNotificationEnabled {
                notify(
                    title: "\(appName) - Login Required",
                    body: "Your 104 session expired. Sign in again.",
                    sound: notificationErrorSound,
                    dryRun: dryRun
                )
            } else {
                await notifyMissedPunchAfterThresholdIfNeeded(
                    action: action,
                    schedule: schedule,
                    scheduledDate: scheduledDate,
                    threshold: max(0, config.missedPunchNotificationDelay),
                    dryRun: dryRun
                )
            }
            return 1
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
                    threshold: max(0, config.missedPunchNotificationDelay),
                    dryRun: dryRun
                )
            }
            return 1
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

    private static let sessionRefreshTimeoutSeconds: TimeInterval = 20
    private static let sessionRefreshPollIntervalNanos: UInt64 = 500_000_000

    private static func awaitFreshSession(
        baseline: Date?,
        timeout: TimeInterval,
        component: String
    ) async -> StoredSession? {
        Log.info(component, "session_refresh_requested", ["timeout_s": Int(timeout)])
        SessionRefreshSignal.post()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let session = AuthStore.loadSession(), session.hasUsableCookies {
                if let baseline {
                    if let validated = session.lastValidatedAt, validated > baseline {
                        Log.info(component, "session_refresh_recovered")
                        return session
                    }
                } else {
                    Log.info(component, "session_refresh_recovered")
                    return session
                }
            }
            try? await Task.sleep(nanoseconds: sessionRefreshPollIntervalNanos)
        }
        Log.info(component, "session_refresh_timeout")
        return nil
    }

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
                let calendar = Calendar(identifier: .gregorian)
                let targetDate =
                    calendar.date(
                        bySettingHour: target.hour,
                        minute: target.minute,
                        second: 0,
                        of: now
                    ) ?? now
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
        } catch Clock104Error.unauthorized {
            return nil
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
