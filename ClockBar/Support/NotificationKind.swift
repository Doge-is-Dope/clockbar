import Foundation

enum PunchNotificationKind: String, CaseIterable {
    case late
    case missed = "missed_punch"
    case crossDay = "cross_day"

    var categoryIdentifier: String {
        rawValue
    }

    var hasPunchAction: Bool {
        switch self {
        case .late, .missed: return true
        case .crossDay: return false
        }
    }
}
