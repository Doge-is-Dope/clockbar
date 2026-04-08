import Foundation

struct NextPunch: Codable, Equatable {
    var date: String
    var clockin: String
    var clockout: String
}

enum NextPunchStore {
    static func loadOrGenerate(config: ClockConfig) -> NextPunch {
        let today = todayString()
        if let existing = load(), existing.date == today {
            return existing
        }
        return generate(config: config)
    }

    @discardableResult
    static func generate(config: ClockConfig) -> NextPunch {
        let punch = NextPunch(
            date: todayString(),
            clockin: randomTime(
                from: config.schedule.clockin,
                to: config.schedule.clockinEnd
            ),
            clockout: randomTime(
                from: config.schedule.clockout,
                to: config.schedule.clockoutEnd
            )
        )
        try? save(punch)
        return punch
    }

    static func load() -> NextPunch? {
        guard let data = try? Data(contentsOf: nextPunchPath),
              let punch = try? JSONDecoder.clockStore.decode(NextPunch.self, from: data)
        else { return nil }
        return punch
    }

    private static func save(_ punch: NextPunch) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.clockStore.encode(punch)
        try data.write(to: nextPunchPath, options: .atomic)
    }

    private static func todayString() -> String {
        DateFormatter.statusDateFormatter.string(from: Date())
    }

    private static func randomTime(from start: String, to end: String) -> String {
        let startMin = minutesSinceMidnight(start)
        let endMin = minutesSinceMidnight(end)
        guard endMin > startMin else { return start }
        let randomMin = Int.random(in: startMin...endMin)
        return String(format: "%02d:%02d", randomMin / 60, randomMin % 60)
    }
}
