import Foundation

enum ClockAction: String, Codable, CaseIterable {
    case clockin
    case clockout

    var displayName: String {
        switch self {
        case .clockin:
            return "Clock In"
        case .clockout:
            return "Clock Out"
        }
    }

    var logLabel: String {
        switch self {
        case .clockin:
            return "clock-in"
        case .clockout:
            return "clock-out"
        }
    }

    var iconSystemName: String {
        switch self {
        case .clockin:
            return "arrow.down.to.line"
        case .clockout:
            return "arrow.up.to.line"
        }
    }

    var launchdLabel: String {
        launchdLabelPrefix + rawValue
    }
}
