import Foundation

// MARK: - Auto Punch Engine

enum AutoPunchEngine {
    static func run(action: ClockAction) async -> Int32 {
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
            AutoPunchLog.append("auto \(action.rawValue): FAILED — invalid schedule")
            SystemUI.notify(title: "104 Clock — Failed", body: "Invalid \(action.displayName) schedule.", sound: "Basso")
            return 1
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let scheduledDate = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: now) ?? now
        let minutesLate = now.timeIntervalSince(scheduledDate) / 60
        let wokeRecently = PowerStateMonitor.didWakeRecently()

        if wokeRecently {
            let choice = SystemUI.prompt(
                title: "104 Clock",
                message: "Your Mac just woke after the scheduled \(action.logLabel). Punch now?",
                buttons: ["Skip", "Punch"]
            )
            guard choice == "Punch" else {
                AutoPunchLog.append("auto \(action.rawValue): skipped by user (wake prompt)")
                SystemUI.notify(title: "104 Clock", body: "\(action.displayName) skipped.")
                return 0
            }
            AutoPunchLog.append("auto \(action.rawValue): user chose to punch (wake prompt)")
        } else if minutesLate > Double(config.lateThresholdMin) {
            let choice = SystemUI.prompt(
                title: "104 Clock",
                message: "Missed \(action.logLabel) at \(schedule.displayString). Punch now?",
                buttons: ["Skip", "Punch"]
            )
            guard choice == "Punch" else {
                AutoPunchLog.append("auto \(action.rawValue): skipped by user (late prompt)")
                SystemUI.notify(title: "104 Clock", body: "\(action.displayName) skipped.")
                return 0
            }
            AutoPunchLog.append("auto \(action.rawValue): user chose to punch (late)")
        } else {
            let delay = Int.random(in: 0...max(config.randomDelayMax, 0))
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }

        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            let message = "Open ClockBar and sign in to 104 again."
            AutoPunchLog.append("auto \(action.rawValue): FAILED — missing session")
            SystemUI.notify(title: "104 Clock — Login Required", body: message, sound: "Basso")
            return 1
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)

            if action == .clockout, status.clockIn == nil {
                let message = "Cannot clock out because there is no clock-in record yet."
                AutoPunchLog.append("auto \(action.rawValue): skipped — \(message)")
                SystemUI.notify(title: "104 Clock", body: message)
                return 0
            }

            let existingPunchTime = existingPunch(for: action, in: status)
            if let existingPunchTime {
                AutoPunchLog.append("auto \(action.rawValue): already punched (\(action.fieldName)=\(existingPunchTime))")
                return 0
            }

            try await Clock104API.sendPunch(session: session)
            let verified = try await Clock104API.getStatus(session: session)
            if let punchTime = existingPunch(for: action, in: verified) {
                var message = "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchTime)"
                if action == .clockout, let clockIn = verified.clockIn {
                    message += " (in: \(clockIn))"
                }
                AutoPunchLog.append("auto \(action.rawValue): OK — \(message)")
                SystemUI.notify(title: "104 Clock", body: message)
                return 0
            }

            AutoPunchLog.append("auto \(action.rawValue): punch sent but not verified")
            SystemUI.notify(title: "104 Clock — Warning", body: "Punch sent but not verified.", sound: "Basso")
            return 1
        } catch Clock104Error.unauthorized {
            AuthStore.clear()
            AutoPunchLog.append("auto \(action.rawValue): FAILED — unauthorized")
            SystemUI.notify(title: "104 Clock — Login Required", body: "Your 104 session expired. Sign in again.", sound: "Basso")
            return 1
        } catch {
            AutoPunchLog.append("auto \(action.rawValue): FAILED — \(error.localizedDescription)")
            SystemUI.notify(title: "104 Clock — Failed", body: error.localizedDescription, sound: "Basso")
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
}

// MARK: - Wake Detection

enum PowerStateMonitor {
    static func didWakeRecently(window: TimeInterval = 600) -> Bool {
        let result = Shell.run("/usr/bin/pmset", arguments: ["-g", "log"])
        guard result.status == 0 else { return false }

        let cutoff = Date().addingTimeInterval(-window)
        let lines = result.stdout.split(separator: "\n").suffix(250)
        for line in lines.reversed() {
            let text = String(line)
            guard text.contains("lidopen") || text.contains("Wake ") || text.contains("DarkWake") else { continue }
            guard let date = DateFormatter.pmsetFormatter.date(from: String(text.prefix(25))) else { continue }
            return date >= cutoff
        }

        return false
    }
}
