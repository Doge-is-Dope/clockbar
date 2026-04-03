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

    var fieldName: String {
        switch self {
        case .clockin:
            return "clockIn"
        case .clockout:
            return "clockOut"
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

    var launchdLabel: String {
        "com.clockbar.104-\(rawValue)"
    }
}
