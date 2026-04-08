import Foundation

struct ScheduledTime: Codable, Equatable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(totalMinutes: Int) {
        let normalized = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        self.init(hour: normalized / 60, minute: normalized % 60)
    }

    init?(string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(hour: parts[0], minute: parts[1])
    }

    var totalMinutes: Int {
        hour * 60 + minute
    }

    var displayString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var shortDisplayString: String {
        let period = hour >= 12 ? "PM" : "AM"
        let hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", hour12, minute, period)
    }

    func date(
        on referenceDate: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay)
            ?? startOfDay
    }
}
