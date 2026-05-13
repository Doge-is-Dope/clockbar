import Foundation

enum PunchNotificationKind: String, CaseIterable {
    case late
    case missed = "missed_punch"
    case crossDay = "cross_day"
    case reloginSoon = "relogin_soon"

    var categoryIdentifier: String {
        rawValue
    }

    var hasPunchAction: Bool {
        switch self {
        case .late, .missed: return true
        case .crossDay, .reloginSoon: return false
        }
    }

    var hasSignInAction: Bool {
        self == .reloginSoon
    }
}
