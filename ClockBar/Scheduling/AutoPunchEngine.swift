import Foundation

enum AutoPunchEngine {
    static func run(action: ClockAction, dryRun: Bool = false) async -> Int32 {
        let config = ConfigManager.load()

        if FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) || !config.autopunchEnabled {
            AutoPunchLog.append("auto \(action.rawValue): skipped (disabled)")
            return 0
        }

        if await HolidayStore.isHoliday() {
            AutoPunchLog.append("auto \(action.rawValue): skipped (holiday)")
            return 0
        }

        guard let schedule = ScheduledTime(string: config.schedule.time(for: action)) else {
            AutoPunchLog.append("auto \(action.rawValue): FAILED - invalid schedule")
            notify(
                title: "104 Clock - Failed",
                body: "Invalid \(action.displayName) schedule.",
                sound: "Basso",
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
        let minutesLate = now.timeIntervalSince(scheduledDate) / 60
        let wokeRecently = dryRun ? false : PowerStateMonitor.didWakeRecently()

        if wokeRecently {
            if dryRun {
                print("[dry-run] Would ask wake prompt for scheduled \(action.logLabel)")
            } else {
                let choice = SystemUI.prompt(
                    title: "104 Clock",
                    message: "Your Mac just woke after the scheduled \(action.logLabel). Punch now?",
                    buttons: ["Skip", "Punch"]
                )
                guard choice == "Punch" else {
                    AutoPunchLog.append("auto \(action.rawValue): skipped by user (wake prompt)")
                    notify(title: "104 Clock", body: "\(action.displayName) skipped.", dryRun: dryRun)
                    return 0
                }
                AutoPunchLog.append("auto \(action.rawValue): user chose to punch (wake prompt)")
            }
        } else if minutesLate > Double(config.lateThresholdMin) {
            if dryRun {
                print("[dry-run] Would ask late prompt for \(action.logLabel) at \(schedule.displayString)")
            } else {
                let choice = SystemUI.prompt(
                    title: "104 Clock",
                    message: "Missed \(action.logLabel) at \(schedule.displayString). Punch now?",
                    buttons: ["Skip", "Punch"]
                )
                guard choice == "Punch" else {
                    AutoPunchLog.append("auto \(action.rawValue): skipped by user (late prompt)")
                    notify(title: "104 Clock", body: "\(action.displayName) skipped.", dryRun: dryRun)
                    return 0
                }
                AutoPunchLog.append("auto \(action.rawValue): user chose to punch (late)")
            }
        } else {
            let delay = Int.random(in: 0...max(config.randomDelayMax, 0))
            if dryRun {
                print("[dry-run] Would sleep \(delay)s (\(delay / 60)m\(delay % 60)s)")
            } else if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }

        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            AutoPunchLog.append("auto \(action.rawValue): FAILED - missing session")
            notify(
                title: "104 Clock - Login Required",
                body: "Open ClockBar and sign in to 104 again.",
                sound: "Basso",
                dryRun: dryRun
            )
            return 1
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)

            if action == .clockout, status.clockIn == nil {
                let message = "Cannot clock out because there is no clock-in record yet."
                AutoPunchLog.append("auto \(action.rawValue): skipped - \(message)")
                notify(title: "104 Clock", body: message, dryRun: dryRun)
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
                notify(title: "104 Clock", body: message, dryRun: dryRun)
                return 0
            }

            AutoPunchLog.append("auto \(action.rawValue): punch sent but not verified")
            notify(
                title: "104 Clock - Warning",
                body: "Punch sent but not verified.",
                sound: "Basso",
                dryRun: dryRun
            )
            return 1
        } catch Clock104Error.unauthorized {
            AuthStore.clear()
            AutoPunchLog.append("auto \(action.rawValue): FAILED - unauthorized")
            notify(
                title: "104 Clock - Login Required",
                body: "Your 104 session expired. Sign in again.",
                sound: "Basso",
                dryRun: dryRun
            )
            return 1
        } catch {
            AutoPunchLog.append("auto \(action.rawValue): FAILED - \(error.localizedDescription)")
            notify(
                title: "104 Clock - Failed",
                body: error.localizedDescription,
                sound: "Basso",
                dryRun: dryRun
            )
            return 1
        }
    }

    private static func existingPunch(for action: ClockAction, in status: PunchStatus) -> String? {
        switch action {
        case .clockin:
            return status.clockIn
        case .clockout:
            return status.clockOut
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
