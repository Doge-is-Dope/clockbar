import Foundation

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
    var minWorkHours: Int
    var latePromptEnabled: Bool
    var lateThreshold: Int
    var autopunchEnabled: Bool
    var wakeEnabled: Bool
    var wakeBefore: Int
    var refreshInterval: Int

    struct Schedule: Codable, Equatable {
        var clockin: String
        var clockinEnd: String
        var clockout: String
        var clockoutEnd: String

        enum CodingKeys: String, CodingKey {
            case clockin
            case clockinEnd = "clockin_end"
            case clockout
            case clockoutEnd = "clockout_end"
        }

        func time(for action: ClockAction) -> String {
            switch action {
            case .clockin: return clockin
            case .clockout: return clockout
            }
        }

        func endTime(for action: ClockAction) -> String {
            switch action {
            case .clockin: return clockinEnd
            case .clockout: return clockoutEnd
            }
        }

        func delayMax(for action: ClockAction) -> Int {
            let start = time(for: action)
            let end = endTime(for: action)
            return max(0, minutesBetween(start, end) * 60)
        }
    }

    enum CodingKeys: String, CodingKey {
        case schedule
        case minWorkHours = "min_work_hours"
        case latePromptEnabled = "late_prompt_enabled"
        case lateThreshold = "late_threshold"
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBefore = "wake_before"
        case refreshInterval = "refresh_interval"
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockinEnd: "09:15", clockout: "18:00", clockoutEnd: "18:15"),
        minWorkHours: 9,
        latePromptEnabled: true,
        lateThreshold: 1200,
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBefore: 300,
        refreshInterval: 1800
    )
}
