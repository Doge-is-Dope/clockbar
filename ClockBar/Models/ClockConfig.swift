import Foundation

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
    var latePromptEnabled: Bool
    var lateThreshold: Int
    var randomDelayMax: Int
    var autopunchEnabled: Bool
    var wakeEnabled: Bool
    var wakeBefore: Int
    var refreshInterval: Int

    struct Schedule: Codable, Equatable {
        var clockin: String
        var clockout: String

        func time(for action: ClockAction) -> String {
            switch action {
            case .clockin:
                return clockin
            case .clockout:
                return clockout
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case schedule
        case latePromptEnabled = "late_prompt_enabled"
        case lateThreshold = "late_threshold"
        case randomDelayMax = "random_delay_max"
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBefore = "wake_before"
        case refreshInterval = "refresh_interval"
    }

    init(
        schedule: Schedule,
        latePromptEnabled: Bool,
        lateThreshold: Int,
        randomDelayMax: Int,
        autopunchEnabled: Bool,
        wakeEnabled: Bool,
        wakeBefore: Int,
        refreshInterval: Int
    ) {
        self.schedule = schedule
        self.latePromptEnabled = latePromptEnabled
        self.lateThreshold = lateThreshold
        self.randomDelayMax = randomDelayMax
        self.autopunchEnabled = autopunchEnabled
        self.wakeEnabled = wakeEnabled
        self.wakeBefore = wakeBefore
        self.refreshInterval = refreshInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        latePromptEnabled = try container.decodeIfPresent(Bool.self, forKey: .latePromptEnabled) ?? true
        lateThreshold = try container.decode(Int.self, forKey: .lateThreshold)
        randomDelayMax = try container.decode(Int.self, forKey: .randomDelayMax)
        autopunchEnabled = try container.decode(Bool.self, forKey: .autopunchEnabled)
        wakeEnabled = try container.decode(Bool.self, forKey: .wakeEnabled)
        wakeBefore = try container.decode(Int.self, forKey: .wakeBefore)
        refreshInterval = try container.decode(Int.self, forKey: .refreshInterval)
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockout: "18:00"),
        latePromptEnabled: true,
        lateThreshold: 1200,
        randomDelayMax: 900,
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBefore: 300,
        refreshInterval: 1800
    )
}
