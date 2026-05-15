import Foundation

@MainActor
final class PunchReminderCoordinator {
    private var inFlight = false

    func checkPending(reason: String) {
        guard !inFlight else { return }
        inFlight = true
        Task { @MainActor in
            defer { inFlight = false }
            await runCheck(reason: reason)
        }
    }

    private func runCheck(reason: String) async {
        Log.info("coordinator", "started", ["trigger": reason])

        let config = ConfigManager.load()
        guard config.missedPunchNotificationEnabled else { return }
        if FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) { return }

        let now = Date()
        if await HolidayStore.isHoliday(on: now) {
            Log.info("coordinator", "skipped", ["reason": "holiday"])
            return
        }

        let status = await ClockService.getStatus()
        if status.error != nil {
            Log.info("coordinator", "skipped", ["reason": "status_error"])
            return
        }

        let today = DateFormatter.statusDate.string(from: now)
        let calendar = Calendar(identifier: .gregorian)
        let grace = config.notificationDelaySeconds

        for action in ClockAction.allCases {
            if action == .clockout, status.clockIn == nil { continue }
            if status.punchTime(for: action) != nil { continue }

            guard let schedule = ScheduledTime(string: config.schedule.time(for: action)),
                let scheduledDate = calendar.date(
                    bySettingHour: schedule.hour,
                    minute: schedule.minute,
                    second: 0,
                    of: now
                )
            else { continue }

            let secondsLate = Int(now.timeIntervalSince(scheduledDate))
            guard secondsLate > 0 else { continue }

            let kind: PunchNotificationKind = secondsLate > grace ? .missed : .late
            if NotificationLedger.shared.hasFired(kind: kind, action: action, date: today) { continue }

            postNotification(kind: kind, action: action)
            NotificationLedger.shared.record(kind: kind, action: action, date: today)
        }
    }

    private func postNotification(kind: PunchNotificationKind, action: ClockAction) {
        let body: String
        switch kind {
        case .late:
            body = "Time to \(action.displayName.lowercased()). Tap Punch Now to record it."
        case .missed:
            body = "\(action.displayName) is overdue. Tap Punch Now to record it."
        case .crossDay:
            body = "Yesterday's \(action.logLabel) is missing — file a correction in 104."
        case .reloginSoon:
            // Not produced by the reminder coordinator (StatusViewModel posts it).
            return
        }
        NotificationManager.shared.send(appName, body: body, categoryIdentifier: kind.categoryIdentifier)
        Log.info(
            "coordinator", "notified",
            [
                "kind": kind.rawValue,
                "action": action.rawValue,
            ])
    }
}
