import Foundation

enum AutoPunchEngine {
    static func run(action: ClockAction, dryRun: Bool = false) async -> Int32 {
        let config = ConfigManager.load()

        if FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path)
            || (!config.autopunchEnabled && !config.missedPunchNotificationEnabled) {
            AutoPunchLog.append("auto \(action.rawValue): skipped (disabled)")
            return 0
        }

        let notificationOnly = !config.autopunchEnabled

        if await HolidayStore.isHoliday() {
            AutoPunchLog.append("auto \(action.rawValue): skipped (holiday)")
            return 0
        }

        guard let schedule = ScheduledTime(string: config.schedule.time(for: action)) else {
            AutoPunchLog.append("auto \(action.rawValue): FAILED - invalid schedule")
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
        let wokeRecently = dryRun ? false : PowerStateMonitor.didWakeRecently()

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
                let choice = SystemUI.prompt(
                    title: appName,
                    message: "Your Mac just woke after the scheduled \(action.logLabel). Punch now?",
                    buttons: ["Skip", "Punch"]
                )
                guard choice == "Punch" else {
                    AutoPunchLog.append("auto \(action.rawValue): skipped by user (wake prompt)")
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
                AutoPunchLog.append("auto \(action.rawValue): user chose to punch (wake prompt)")
            }
        } else {
            let delay = Self.computeDelay(for: action, config: config)
            if dryRun {
                print("[dry-run] Would sleep \(delay)s (\(delay / 60)m\(delay % 60)s)")
            } else if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }

        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            AutoPunchLog.append("auto \(action.rawValue): FAILED - missing session")
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

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)

            if action == .clockout, status.clockIn == nil {
                let message = "Cannot clock out because there is no clock-in record yet."
                AutoPunchLog.append("auto \(action.rawValue): skipped - \(message)")
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
                AutoPunchLog.append(
                    "auto \(action.rawValue): already punched (\(action.fieldName)=\(existingPunchTime))"
                )
                return 0
            }

            if dryRun {
                let statusData = try? JSONEncoder.clockStore.encode(status)
                if let statusData {
                    print("[dry-run] Would punch (\(action.rawValue))")
                    print("[dry-run] Current status: \(String(decoding: statusData, as: UTF8.self))")
                }
                AutoPunchLog.append("auto \(action.rawValue): dry-run OK")
                return 0
            }

            try await Clock104API.sendPunch(session: session)
            let verified = try await Clock104API.getStatus(session: session)
            if let punchTime = existingPunch(for: action, in: verified) {
                var message = "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchTime)"
                if action == .clockout, let clockIn = verified.clockIn {
                    message += " (in: \(clockIn))"
                }
                AutoPunchLog.append("auto \(action.rawValue): OK - \(message)")
                notify(title: appName, body: message, dryRun: dryRun)
                return 0
            }

            AutoPunchLog.append("auto \(action.rawValue): punch sent but not verified")
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
            AuthStore.clear()
            AutoPunchLog.append("auto \(action.rawValue): FAILED - unauthorized")
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
            AutoPunchLog.append("auto \(action.rawValue): FAILED - \(error.localizedDescription)")
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
        let remainingDelay = max(0, threshold - Int(Date().timeIntervalSince(scheduledDate)))

        if dryRun {
            print("[dry-run] Would wait \(remainingDelay)s before checking missed \(action.logLabel)")
        } else if remainingDelay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remainingDelay) * 1_000_000_000)
            } catch {
                AutoPunchLog.append("notification \(action.rawValue): cancelled during missed-punch delay")
                return
            }
        }

        let status = await currentStatusForMissedPunchCheck()
        if let status, existingPunch(for: action, in: status) != nil {
            AutoPunchLog.append("notification \(action.rawValue): skipped - already punched")
            return
        }

        let body: String
        if status == nil {
            body = "Scheduled \(action.logLabel) at \(schedule.displayString) is still unconfirmed. Open ClockBar to check 104."
        } else {
            body = "No \(action.logLabel) was recorded after the scheduled time (\(schedule.displayString))."
        }

        AutoPunchLog.append("notification \(action.rawValue): missed punch")
        notify(title: appName, body: body, dryRun: dryRun)
    }

    private static func computeDelay(for action: ClockAction, config: ClockConfig) -> Int {
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
                return max(0, Int(targetDate.timeIntervalSince(now)))
            }
        }

        // Fallback: random delay if no pre-computed time
        return Int.random(in: 0...max(config.schedule.delayMax(for: action), 0))
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
            AuthStore.clear()
            return nil
        } catch {
            return nil
        }
    }

    private static func notify(
        title: String,
        body: String,
        sound: String = "default",
        dryRun: Bool
    ) {
        guard !dryRun else {
            print("[dry-run] Would notify \"\(title)\": \(body)")
            return
        }

        SystemUI.notify(title: title, body: body, sound: sound)
    }
}
