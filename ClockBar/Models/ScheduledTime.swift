import Foundation

struct ScheduledTime: Codable, Equatable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(hour: parts[0], minute: parts[1])
    }

    var displayString: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
