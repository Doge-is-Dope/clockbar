import Foundation

struct PunchStatus: Codable, Equatable {
    let date: String?
    let clockIn: String?
    let clockOut: String?
    let clockInCode: Int?
    let error: String?

    static func error(_ message: String) -> PunchStatus {
        PunchStatus(
            date: DateFormatter.statusDate.string(from: Date()),
            clockIn: nil,
            clockOut: nil,
            clockInCode: nil,
            error: message
        )
    }

    /// "No session loaded" status. Use when surfacing as `PunchStatus`; throw
    /// `Clock104Error.missingSession` when bubbling through the API layer.
    static var signedOut: PunchStatus {
        .error("Sign in to 104 to enable status and punching.")
    }

    func punchTime(for action: ClockAction) -> String? {
        switch action {
        case .clockin: return clockIn
        case .clockout: return clockOut
        }
    }
}
