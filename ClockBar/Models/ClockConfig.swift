import Foundation

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
    var minWorkHours: Int
    var missedPunchNotificationEnabled: Bool
    var missedPunchNotificationDelay: Int
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

        init(
            clockin: String,
            clockinEnd: String,
            clockout: String,
            clockoutEnd: String
        ) {
            self.clockin = clockin
            self.clockinEnd = clockinEnd
            self.clockout = clockout
            self.clockoutEnd = clockoutEnd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ClockConfig.default.schedule
            self.clockin = try container.decodeIfPresent(String.self, forKey: .clockin) ?? defaults.clockin
            self.clockinEnd = try container.decodeIfPresent(String.self, forKey: .clockinEnd) ?? defaults.clockinEnd
            self.clockout = try container.decodeIfPresent(String.self, forKey: .clockout) ?? defaults.clockout
            self.clockoutEnd = try container.decodeIfPresent(String.self, forKey: .clockoutEnd) ?? defaults.clockoutEnd
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
        case missedPunchNotificationEnabled = "missed_punch_notification_enabled"
        case missedPunchNotificationDelay = "missed_punch_notification_delay"
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBefore = "wake_before"
        case refreshInterval = "refresh_interval"
    }

    init(
        schedule: Schedule,
        minWorkHours: Int,
        missedPunchNotificationEnabled: Bool,
        missedPunchNotificationDelay: Int,
        autopunchEnabled: Bool,
        wakeEnabled: Bool,
        wakeBefore: Int,
        refreshInterval: Int
    ) {
        self.schedule = schedule
        self.minWorkHours = minWorkHours
        self.missedPunchNotificationEnabled = missedPunchNotificationEnabled
        self.missedPunchNotificationDelay = missedPunchNotificationDelay
        self.autopunchEnabled = autopunchEnabled
        self.wakeEnabled = wakeEnabled
        self.wakeBefore = wakeBefore
        self.refreshInterval = refreshInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClockConfig.default
        self.schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule) ?? defaults.schedule
        self.minWorkHours = try container.decodeIfPresent(Int.self, forKey: .minWorkHours) ?? defaults.minWorkHours
        self.missedPunchNotificationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .missedPunchNotificationEnabled)
            ?? defaults.missedPunchNotificationEnabled
        self.missedPunchNotificationDelay =
            try container.decodeIfPresent(Int.self, forKey: .missedPunchNotificationDelay)
            ?? defaults.missedPunchNotificationDelay
        self.autopunchEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .autopunchEnabled) ?? defaults.autopunchEnabled
        self.wakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .wakeEnabled) ?? defaults.wakeEnabled
        self.wakeBefore = try container.decodeIfPresent(Int.self, forKey: .wakeBefore) ?? defaults.wakeBefore
        self.refreshInterval =
            try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? defaults.refreshInterval
    }

    var requiresScheduledJobs: Bool {
        autopunchEnabled || missedPunchNotificationEnabled
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockinEnd: "09:15", clockout: "18:00", clockoutEnd: "18:15"),
        minWorkHours: 9,
        missedPunchNotificationEnabled: true,
        missedPunchNotificationDelay: 0,
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBefore: 300,
        refreshInterval: 1800
    )
}
