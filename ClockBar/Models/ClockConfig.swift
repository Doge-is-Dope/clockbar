import Foundation

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
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
        case lateThreshold = "late_threshold"
        case randomDelayMax = "random_delay_max"
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBefore = "wake_before"
        case refreshInterval = "refresh_interval"
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockout: "18:00"),
        lateThreshold: 1200,
        randomDelayMax: 900,
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBefore: 300,
        refreshInterval: 1800
    )
}
