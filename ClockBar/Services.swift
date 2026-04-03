import Foundation
import Security

// MARK: - Config Manager

enum ConfigManager {
    static func load() -> ClockConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder.clockStore.decode(ClockConfig.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: ClockConfig) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.clockStore.encode(config)
        try data.write(to: configPath, options: .atomic)
    }
}

// MARK: - Auth Store

enum AuthStore {
    private static let service = "com.clockbar.104.clockbar.session"
    private static let account = "default"

    static func loadSession() -> StoredSession? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder.clockStore.decode(StoredSession.self, from: data)
        else { return nil }
        return session
    }

    static func save(_ session: StoredSession) throws {
        let data = try JSONEncoder.clockStore.encode(session)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Clock104Error.keychain("Unable to update saved session (\(updateStatus)).")
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw Clock104Error.keychain("Unable to save session (\(addStatus)).")
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - API

enum Clock104Error: LocalizedError {
    case missingSession
    case unauthorized
    case invalidResponse(String)
    case api(String)
    case keychain(String)
    case scheduler(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Sign in to 104 to continue."
        case .unauthorized:
            return "Your 104 session expired. Sign in again."
        case .invalidResponse(let message), .api(let message), .keychain(let message), .scheduler(let message):
            return message
        }
    }
}

enum Clock104API {
    static func validate(session: StoredSession) async throws -> StoredSession {
        _ = try await getStatus(session: session)
        var updated = session
        updated.lastValidatedAt = Date()
        return updated
    }

    static func getStatus(session: StoredSession) async throws -> PunchStatus {
        guard session.hasUsableCookies else { throw Clock104Error.missingSession }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let range = calendar.range(of: .day, in: .month, for: now) ?? 1..<32
        var endComponents = calendar.dateComponents([.year, .month], from: now)
        endComponents.day = range.count
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59
        let endOfMonth = calendar.date(from: endComponents) ?? now

        let startMS = Int(startOfMonth.timeIntervalSince1970 * 1000)
        let endMS = Int(endOfMonth.timeIntervalSince1970 * 1000)
        let json = try await requestJSON(
            path: "/psc2/api/home/newCalendar/\(startMS)/\(endMS)",
            method: "GET",
            session: session
        )

        if (json["code"] as? Int) == 401 {
            throw Clock104Error.unauthorized
        }

        guard let entries = json["data"] as? [[String: Any]] else {
            throw Clock104Error.invalidResponse("Unable to parse attendance status.")
        }

        let today = calendar.startOfDay(for: now)
        for entry in entries {
            guard let dateMS = entry["date"] as? Double ?? (entry["date"] as? Int).map(Double.init) else { continue }
            let entryDate = calendar.startOfDay(for: Date(timeIntervalSince1970: dateMS / 1000))
            guard entryDate == today else { continue }

            let clockInfo = entry["clockIn"] as? [String: Any] ?? [:]
            let startTime = formatTimestamp(clockInfo["start"])
            let endTime = formatTimestamp(clockInfo["end"])
            let code = clockInfo["clockInCode"] as? Int
            return PunchStatus(
                date: DateFormatter.statusDateFormatter.string(from: now),
                clockIn: startTime,
                clockOut: endTime,
                clockInCode: code,
                error: nil
            )
        }

        return PunchStatus(
            date: DateFormatter.statusDateFormatter.string(from: now),
            clockIn: nil,
            clockOut: nil,
            clockInCode: nil,
            error: nil
        )
    }

    static func sendPunch(session: StoredSession) async throws {
        guard session.hasUsableCookies else { throw Clock104Error.missingSession }
        let json = try await requestJSON(
            path: "/psc2/api/f0400/newClockin",
            method: "POST",
            session: session
        )

        if (json["code"] as? Int) == 401 {
            throw Clock104Error.unauthorized
        }

        if let code = json["code"] as? Int, code != 200 {
            let message = json["message"] as? String ?? "Punch failed."
            throw Clock104Error.api(message)
        }
    }

    private static func requestJSON(
        path: String,
        method: String,
        session: StoredSession
    ) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("JSON", forHTTPHeaderField: "X-Request")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        if method == "POST" {
            request.httpBody = Data()
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Clock104Error.invalidResponse("No HTTP response from 104.")
        }

        if http.statusCode == 401 {
            throw Clock104Error.unauthorized
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Clock104Error.invalidResponse("104 returned malformed JSON.")
        }

        return json
    }

    private static func formatTimestamp(_ value: Any?) -> String? {
        guard let milliseconds = value as? Double ?? (value as? Int).map(Double.init) else { return nil }
        return DateFormatter.shortTimeFormatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}

// MARK: - Clock Service

enum ClockService {
    static func getStatus() async -> PunchStatus {
        guard var session = AuthStore.loadSession() else {
            return .error("Sign in to 104 to enable status and punching.")
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)
            return status
        } catch Clock104Error.unauthorized {
            AuthStore.clear()
            return .error("Your 104 session expired. Sign in again.")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func punch() async -> PunchStatus {
        guard var session = AuthStore.loadSession() else {
            return .error("Sign in to 104 before punching.")
        }

        do {
            try await Clock104API.sendPunch(session: session)
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)
            return status
        } catch Clock104Error.unauthorized {
            AuthStore.clear()
            return .error("Your 104 session expired. Sign in again.")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func createStoredSession(from cookies: [HTTPCookie]) async throws -> StoredSession {
        let relevantCookies = cookies.filter { $0.domain.contains("104") }
        guard !relevantCookies.isEmpty else {
            throw Clock104Error.missingSession
        }

        let session = StoredSession(
            cookies: relevantCookies.map(StoredCookie.init(cookie:)),
            lastValidatedAt: nil
        )
        return try await Clock104API.validate(session: session)
    }

    static func saveSession(_ session: StoredSession) throws {
        try AuthStore.save(session)
    }

    static func clearSession() {
        AuthStore.clear()
    }

    static func scheduleInstall(for config: ClockConfig) throws -> ScheduleState {
        try ConfigManager.save(config)
        return try LaunchAgentManager.install(config: config)
    }

    static func saveConfig(_ config: ClockConfig) throws {
        try ConfigManager.save(config)
    }

    static func currentScheduleState(config: ClockConfig) -> ScheduleState {
        LaunchAgentManager.currentState(config: config)
    }
}

// MARK: - Formatting

extension JSONEncoder {
    static let clockStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
}

extension JSONDecoder {
    static let clockStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

extension DateFormatter {
    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let taiwanHolidayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static let pmsetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}

extension String {
    func firstInteger(matching pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return Int(self[range])
    }
}
