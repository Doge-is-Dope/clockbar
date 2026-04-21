import Foundation

enum AutoPunchEngine {
    static func run(action: ClockAction, dryRun: Bool = false) async -> Int32 {
        let component = "auto.\(action.rawValue)"
        let argv = CommandLine.arguments.dropFirst().joined(separator: " ")
        Log.info(component, "invoked", [
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
            || (!config.autopunchEnabled && !config.missedPunchNotificationEnabled) {
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
        let scheduledDate = calendar.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: now
        ) ?? now
        let recentWake = dryRun ? nil : PowerStateMonitor.recentWake()
        let wokeRecently = recentWake != nil
        if let recentWake {
            Log.info(component, "woke_recently", [
                "kind": recentWake.kind.rawValue,
                "at": DateFormatter.logTimestampFormatter.string(from: recentWake.date),
            ])
        } else if !dryRun {
            Log.info(component, "woke_recently", ["value": "false"])
        }

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

        if wokeRecently {
            if dryRun {
                print("[dry-run] Would ask wake prompt for scheduled \(action.logLabel)")
            } else {
                Log.info(component, "wake_prompt_shown")
                let choice = SystemUI.prompt(
                    title: appName,
                    message: "Your Mac just woke after the scheduled \(action.logLabel). Punch now?",
                    buttons: ["Skip", "Punch"]
                )
                Log.info(component, "wake_prompt_result", ["choice": choice ?? "nil"])
                guard choice == "Punch" else {
                    Log.info(component, "skipped", ["reason": "user_skipped_at_wake_prompt"])
                    notify(title: appName, body: "\(action.displayName) skipped.", dryRun: dryRun)
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
                Log.info(component, "wake_prompt_confirmed")
            }
        } else {
            let plan = Self.computeDelayPlan(for: action, config: config)
            let targetText = plan.target?.displayString ?? "(\(plan.delay)s from now)"
            Log.info(component, "sleeping", [
                "delay_s": plan.delay,
                "target": targetText,
                "source": plan.source.rawValue,
            ])
            if dryRun {
                print("[dry-run] Would sleep \(plan.delay)s (\(plan.delay / 60)m\(plan.delay % 60)s)")
            } else if plan.delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(plan.delay) * 1_000_000_000)
            }
        }

        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            Log.error(component, "failed", ["reason": "missing_session"])
            notify(
                title: "\(appName) - Login Required",
                body: "Open ClockBar and sign in to 104 again.",
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

            if let existingPunchTime = existingPunch(for: action, in: status) {
                Log.info(component, "already_punched", [
                    "field": action.fieldName,
                    "value": existingPunchTime,
                ])
                return 0
            }

            if dryRun {
                let statusData = try? JSONEncoder.clockStore.encode(status)
                if let statusData {
                    print("[dry-run] Would punch (\(action.rawValue))")
                    print("[dry-run] Current status: \(String(decoding: statusData, as: UTF8.self))")
                }
                Log.info(component, "dry_run_ok")
                return 0
            }

            currentStep = "sendPunch"
            Log.info(component, "step", ["name": "sendPunch"])
            try await Clock104API.sendPunch(session: session)
            currentStep = "verifyStatus"
            Log.info(component, "step", ["name": "verifyStatus"])
            let verified = try await Clock104API.getStatus(session: session)
            if let punchTime = existingPunch(for: action, in: verified) {
                var message = "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchTime)"
                if action == .clockout, let clockIn = verified.clockIn {
                    message += " (in: \(clockIn))"
                }
                if action == .clockout, let clockIn = verified.clockIn {
                    Log.info(component, "ok", [
                        "punched_at": punchTime,
                        "previous_in": clockIn,
                    ])
                } else {
                    Log.info(component, "ok", ["punched_at": punchTime])
                }
                notify(title: appName, body: message, dryRun: dryRun)
                return 0
            }

            Log.warn(component, "unverified")
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
            Log.error(component, "failed", [
                "reason": "unauthorized",
                "step": currentStep,
            ])
            notify(
                title: "\(appName) - Login Required",
                body: "Your 104 session expired. Sign in again.",
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
        } catch {
            Log.error(component, "failed", [
                "reason": error.localizedDescription,
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
        if let status, existingPunch(for: action, in: status) != nil {
            Log.info(component, "skipped", ["reason": "already_punched"])
            return
        }

        let body = "Scheduled \(action.logLabel) at \(schedule.displayString) has passed."

        Log.warn(component, "missed_punch")
        notify(title: appName, body: body, kind: .missedPunch(action), dryRun: dryRun)
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
        let today = DateFormatter.statusDateFormatter.string(from: Date())

        if let punch = NextPunchStore.load(), punch.date == today {
            let targetTime = action == .clockin ? punch.clockin : punch.clockout
            if let target = ScheduledTime(string: targetTime) {
                let now = Date()
                let calendar = Calendar(identifier: .gregorian)
                let targetDate = calendar.date(
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

    private static func existingPunch(for action: ClockAction, in status: PunchStatus) -> String? {
        switch action {
        case .clockin:
            return status.clockIn
        case .clockout:
            return status.clockOut
        }
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
