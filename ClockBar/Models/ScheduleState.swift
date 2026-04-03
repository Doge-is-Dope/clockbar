import Foundation

struct ScheduleJobState: Equatable {
    let action: ClockAction
    let configuredTime: ScheduledTime?
    let installedTime: ScheduledTime?
    let loadedTime: ScheduledTime?
    let isLoaded: Bool
    let issue: String?

    var isInSync: Bool {
        configuredTime == installedTime && installedTime == loadedTime && isLoaded
    }
}

struct ScheduleState: Equatable {
    let jobs: [ScheduleJobState]
    let lastError: String?

    var mismatchSummary: String? {
        if let issue = jobs.compactMap(\.issue).first {
            return issue
        }

        if jobs.contains(where: { !$0.isInSync }) {
            return "Auto-punch schedule is out of sync with launchd."
        }

        return lastError
    }
}
