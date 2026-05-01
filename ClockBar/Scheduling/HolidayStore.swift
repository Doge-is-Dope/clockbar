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
        let calendar = Calendar(identifier: .gregorian)
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
               (response as? HTTPURLResponse)?.statusCode == 200 {
                try? data.write(to: cacheURL, options: .atomic)
            }
        }

        guard let data = try? Data(contentsOf: cacheURL),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return HolidayLookup(isHoliday: calendar.isDateInWeekend(date), name: "")
        }

        let todayString = DateFormatter.taiwanHolidayFormatter.string(from: date)
        for entry in entries where (entry["date"] as? String) == todayString {
            return HolidayLookup(
                isHoliday: (entry["isHoliday"] as? Bool) ?? false,
                name: (entry["description"] as? String) ?? ""
            )
        }

        return HolidayLookup(isHoliday: calendar.isDateInWeekend(date), name: "")
    }
}
