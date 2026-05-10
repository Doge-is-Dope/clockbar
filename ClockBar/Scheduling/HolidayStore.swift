import Foundation

struct HolidayLookup {
    let isHoliday: Bool
    /// Holiday name from TaiwanCalendar (e.g. "勞動節"). Empty for weekend
    /// entries with no named holiday, and for weekend fallbacks when the
    /// cache is missing.
    let name: String
}

enum HolidayStore {
    static func isHoliday(on date: Date = Date()) async -> Bool {
        await lookup(on: date).isHoliday
    }

    static func lookup(on date: Date = Date()) async -> HolidayLookup {
        let dayKey = DateFormatter.taiwanHolidayFormatter.string(from: date)

        if let cached = cache.read(forKey: dayKey) {
            return cached
        }

        let calendar = Calendar(identifier: .gregorian)
        if let result = await loadFromSource(on: date, dayKey: dayKey, calendar: calendar) {
            cache.write(result, forKey: dayKey)
            return result
        }

        return HolidayLookup(isHoliday: calendar.isDateInWeekend(date), name: "")
    }

    private static func loadFromSource(
        on date: Date,
        dayKey: String,
        calendar: Calendar
    ) async -> HolidayLookup? {
        let year = calendar.component(.year, from: date)
        let cacheURL = holidayDirectory.appendingPathComponent("\(year).json")

        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: holidayDirectory, withIntermediateDirectories: true)
            if let sourceURL = URL(
                string: holidayBaseURL + "\(year).json"
            ),
                let (data, response) = try? await URLSession.shared.data(
                    for: URLRequest(url: sourceURL, timeoutInterval: 3)
                ),
                (response as? HTTPURLResponse)?.statusCode == 200
            {
                try? data.write(to: cacheURL, options: .atomic)
            }
        }

        guard let data = try? Data(contentsOf: cacheURL),
            let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        for entry in entries where (entry["date"] as? String) == dayKey {
            return HolidayLookup(
                isHoliday: (entry["isHoliday"] as? Bool) ?? false,
                name: (entry["description"] as? String) ?? ""
            )
        }

        return HolidayLookup(isHoliday: calendar.isDateInWeekend(date), name: "")
    }

    private static let cache = LookupCache()
}

private final class LookupCache: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var value: HolidayLookup?

    func read(forKey requested: String) -> HolidayLookup? {
        lock.lock()
        defer { lock.unlock() }
        guard key == requested else { return nil }
        return value
    }

    func write(_ result: HolidayLookup, forKey newKey: String) {
        lock.lock()
        key = newKey
        value = result
        lock.unlock()
    }
}
