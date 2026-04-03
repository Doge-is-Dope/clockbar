import Foundation

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
    var lateThresholdMin: Int
    var randomDelayMax: Int
    var autopunchEnabled: Bool
    var wakeEnabled: Bool
    var wakeBeforeMin: Int

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
        case lateThresholdMin = "late_threshold_min"
        case randomDelayMax = "random_delay_max"
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBeforeMin = "wake_before_min"
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockout: "18:00"),
        lateThresholdMin: 20,
        randomDelayMax: 900,
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBeforeMin: 5
    )
}
