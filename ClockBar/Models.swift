import Foundation

// MARK: - Config Model

struct ClockConfig: Codable, Equatable {
    var schedule: Schedule
    var lateThresholdMin: Int
    var randomDelayMax: Int
    var server: ServerConfig
    var autopunchEnabled: Bool
    var wakeEnabled: Bool
    var wakeBeforeMin: Int

    struct Schedule: Codable, Equatable {
        var clockin: String
        var clockout: String

        func time(for action: ClockAction) -> String {
            switch action {
            case .clockin:
                return clockin
            case .clockout:
                return clockout
            }
        }
    }

    struct ServerConfig: Codable, Equatable {
        var port: Int
        var token: String
    }

    enum CodingKeys: String, CodingKey {
        case schedule
        case lateThresholdMin = "late_threshold_min"
        case randomDelayMax = "random_delay_max"
        case server
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBeforeMin = "wake_before_min"
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockout: "18:00"),
        lateThresholdMin: 20,
        randomDelayMax: 900,
        server: .init(port: 8104, token: ""),
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBeforeMin: 5
    )
}

enum ClockAction: String, Codable, CaseIterable {
    case clockin
    case clockout

    var displayName: String {
        switch self {
        case .clockin:
            return "Clock In"
        case .clockout:
            return "Clock Out"
        }
    }

    var fieldName: String {
        switch self {
        case .clockin:
            return "clockIn"
        case .clockout:
            return "clockOut"
        }
    }

    var logLabel: String {
        switch self {
        case .clockin:
            return "clock-in"
        case .clockout:
            return "clock-out"
        }
    }

    var launchdLabel: String {
        "com.clockbar.104-\(rawValue)"
    }
}

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

// MARK: - Auth Model

struct StoredCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var isSecure: Bool
    var isHTTPOnly: Bool
    var expiresAt: Date?

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = (cookie.properties?[HTTPCookiePropertyKey("HttpOnly")] as? String) == "TRUE"
        self.expiresAt = cookie.expiresDate
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

struct StoredSession: Codable, Equatable {
    var cookies: [StoredCookie]
    var lastValidatedAt: Date?

    var cookieHeader: String {
        cookies
            .filter { !$0.isExpired }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    var hasUsableCookies: Bool {
        !cookieHeader.isEmpty
    }
}

// MARK: - Status Model

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

// MARK: - Scheduler Model

struct ScheduleJobState: Equatable {
    let action: ClockAction
    let configuredTime: ScheduledTime?
    let installedTime: ScheduledTime?
    let loadedTime: ScheduledTime?
    let isLoaded: Bool
    let issue: String?

    var isInSync: Bool {
        configuredTime == installedTime && installedTime == loadedTime && isLoaded
    }
}

struct ScheduleState: Equatable {
    let jobs: [ScheduleJobState]
    let lastError: String?

    var mismatchSummary: String? {
        if let issue = jobs.compactMap(\.issue).first {
            return issue
        }

        if jobs.contains(where: { !$0.isInSync }) {
            return "Auto-punch schedule is out of sync with launchd."
        }

        return lastError
    }

    static func empty(config: ClockConfig) -> ScheduleState {
        ScheduleState(
            jobs: ClockAction.allCases.map {
                ScheduleJobState(
                    action: $0,
                    configuredTime: ScheduledTime(string: config.schedule.time(for: $0)),
                    installedTime: nil,
                    loadedTime: nil,
                    isLoaded: false,
                    issue: nil
                )
            },
            lastError: nil
        )
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
