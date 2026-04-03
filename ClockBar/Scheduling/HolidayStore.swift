import Foundation

enum HolidayStore {
    static func isHoliday(on date: Date = Date()) async -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let cacheURL = holidayDirectory.appendingPathComponent("\(year).json")

        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: holidayDirectory, withIntermediateDirectories: true)
            if let sourceURL = URL(
                string: "https://cdn.jsdelivr.net/gh/ruyut/TaiwanCalendar/data/\(year).json"
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
            return calendar.isDateInWeekend(date)
        }

        let todayString = DateFormatter.taiwanHolidayFormatter.string(from: date)
        for entry in entries where (entry["date"] as? String) == todayString {
            return (entry["isHoliday"] as? Bool) ?? false
        }

        return calendar.isDateInWeekend(date)
    }
}
