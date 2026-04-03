import Foundation

struct PunchStatus: Codable, Equatable {
    let date: String?
    let clockIn: String?
    let clockOut: String?
    let clockInCode: Int?
    let error: String?

    static func error(_ message: String) -> PunchStatus {
        PunchStatus(
            date: DateFormatter.statusDateFormatter.string(from: Date()),
            clockIn: nil,
            clockOut: nil,
            clockInCode: nil,
            error: message
        )
    }
}
