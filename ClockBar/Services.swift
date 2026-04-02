import Foundation
import Security
import UserNotifications

// MARK: - Paths

private let baseURL = URL(string: "https://pro.104.com.tw")!
private let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".104", isDirectory: true)
private let holidayDirectory = cacheDirectory.appendingPathComponent("holidays", isDirectory: true)
private let configPath = cacheDirectory.appendingPathComponent("config.json")
private let autoPunchLogPath = cacheDirectory.appendingPathComponent("auto-punch.log")
private let autoPunchKillSwitchPath = cacheDirectory.appendingPathComponent("autopunch-disabled")
private let launchAgentDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents", isDirectory: true)

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

// MARK: - Notification Manager

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var didSetup = false

    func setup() {
        guard !didSetup else { return }
        didSetup = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ title: String, body: String, sound: UNNotificationSound = .default) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}

// MARK: - Shell

struct ShellResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum Shell {
    static func run(_ executable: String, arguments: [String]) -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, status: 1)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}

enum SystemUI {
    static func notify(title: String, body: String, sound: String = "default") {
        let script = """
        display notification "\(escapeAppleScript(body))" with title "\(escapeAppleScript(title))" sound name "\(escapeAppleScript(sound))"
        """
        _ = Shell.run("/usr/bin/osascript", arguments: ["-e", script])
    }

    static func prompt(title: String, message: String, buttons: [String]) -> String? {
        let buttonList = buttons.map { "\"\(escapeAppleScript($0))\"" }.joined(separator: ", ")
        let script = """
        display dialog "\(escapeAppleScript(message))" with title "\(escapeAppleScript(title))" buttons {\(buttonList)} default button "\(escapeAppleScript(buttons.last ?? "OK"))"
        """
        let result = Shell.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.status == 0 else { return nil }
        for part in result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",") {
            let text = String(part)
            if text.contains("button returned:") {
                return text.split(separator: ":", maxSplits: 1).last.map(String.init)
            }
        }
        return nil
    }

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - Logging

enum AutoPunchLog {
    static func append(_ message: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let timestamp = DateFormatter.logTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: autoPunchLogPath.path),
               let handle = try? FileHandle(forWritingTo: autoPunchLogPath) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: autoPunchLogPath, options: .atomic)
            }
        }
    }
}

// MARK: - Auth Store

enum AuthStore {
    private static let service = "com.clockbar.104.clockbar.session"
    private static let account = "default"

    static func loadSession() -> StoredSession? {
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

// MARK: - Holiday Store

enum HolidayStore {
    static func isHoliday(on date: Date = Date()) async -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let cacheURL = holidayDirectory.appendingPathComponent("\(year).json")

        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: holidayDirectory, withIntermediateDirectories: true)
            if let url = URL(string: "https://cdn.jsdelivr.net/gh/ruyut/TaiwanCalendar/data/\(year).json"),
               let (data, response) = try? await URLSession.shared.data(from: url),
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

// MARK: - Scheduler

enum LaunchAgentManager {
    static func install(config: ClockConfig, helperExecutablePath: String? = nil) throws -> ScheduleState {
        let helperPath = helperExecutablePath ?? bundledHelperExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw Clock104Error.scheduler("Bundled helper is missing at \(helperPath).")
        }

        try FileManager.default.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        for action in ClockAction.allCases {
            let plistPath = plistPath(for: action)
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, plistPath.path])
            let plist = try generatePlist(action: action, config: config, helperExecutablePath: helperPath)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistPath, options: .atomic)

            let bootstrap = Shell.run("/bin/launchctl", arguments: ["bootstrap", guiDomain, plistPath.path])
            guard bootstrap.status == 0 else {
                throw Clock104Error.scheduler(bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let state = currentState(config: config)
        if let mismatch = state.mismatchSummary {
            throw Clock104Error.scheduler(mismatch)
        }
        return state
    }

    static func remove() throws {
        for action in ClockAction.allCases {
            let plist = plistPath(for: action)
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, plist.path])
            try? FileManager.default.removeItem(at: plist)
        }
    }

    static func currentState(config: ClockConfig) -> ScheduleState {
        let jobs = ClockAction.allCases.map { action -> ScheduleJobState in
            let configured = ScheduledTime(string: config.schedule.time(for: action))
            let installed = installedTime(for: action)
            let loaded = loadedTime(for: action)
            let isLoaded = loaded != nil

            let issue: String?
            if configured != installed {
                issue = "\(action.displayName) schedule differs from the installed plist."
            } else if installed != loaded {
                issue = "\(action.displayName) schedule differs from the loaded launchd trigger."
            } else if !isLoaded {
                issue = "\(action.displayName) launchd job is not loaded."
            } else {
                issue = nil
            }

            return ScheduleJobState(
                action: action,
                configuredTime: configured,
                installedTime: installed,
                loadedTime: loaded,
                isLoaded: isLoaded,
                issue: issue
            )
        }

        return ScheduleState(jobs: jobs, lastError: nil)
    }

    static func statusText(config: ClockConfig) -> String {
        let state = currentState(config: config)
        let lines = state.jobs.map { job -> String in
            let configured = job.configuredTime?.displayString ?? "--:--"
            let installed = job.installedTime?.displayString ?? "missing"
            let loaded = job.loadedTime?.displayString ?? "missing"
            let stateText = job.isLoaded ? "loaded" : "not loaded"
            return "  \(job.action.launchdLabel): \(stateText) config=\(configured) plist=\(installed) loaded=\(loaded)"
        }

        var output = ["=== launchd jobs ==="]
        output.append(contentsOf: lines)
        output.append("")
        output.append("=== auto-punch ===")
        output.append("  \(config.autopunchEnabled && !FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) ? "enabled" : "DISABLED")")
        output.append("")
        output.append("=== recent logs ===")
        if let data = try? String(contentsOf: autoPunchLogPath, encoding: .utf8) {
            output.append(contentsOf: data.split(separator: "\n").suffix(10).map { "  \($0)" })
        } else {
            output.append("  (no logs yet)")
        }
        return output.joined(separator: "\n")
    }

    private static func bundledHelperExecutablePath() -> String {
        let bundlePath = Bundle.main.bundlePath
        let candidate = (bundlePath as NSString).appendingPathComponent("Contents/MacOS/clockbar-helper")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return CommandLine.arguments[0]
    }

    private static func plistPath(for action: ClockAction) -> URL {
        launchAgentDirectory.appendingPathComponent("\(action.launchdLabel).plist")
    }

    private static func generatePlist(
        action: ClockAction,
        config: ClockConfig,
        helperExecutablePath: String
    ) throws -> [String: Any] {
        guard let time = ScheduledTime(string: config.schedule.time(for: action)) else {
            throw Clock104Error.scheduler("Invalid \(action.displayName) schedule.")
        }

        return [
            "Label": action.launchdLabel,
            "ProgramArguments": [helperExecutablePath, "auto", action.rawValue],
            "StartCalendarInterval": ["Hour": time.hour, "Minute": time.minute],
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "StandardOutPath": cacheDirectory.appendingPathComponent("launchd-\(action.rawValue).stdout.log").path,
            "StandardErrorPath": cacheDirectory.appendingPathComponent("launchd-\(action.rawValue).stderr.log").path,
        ]
    }

    private static func installedTime(for action: ClockAction) -> ScheduledTime? {
        let path = plistPath(for: action)
        guard let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let calendar = plist["StartCalendarInterval"] as? [String: Any],
              let hour = calendar["Hour"] as? Int,
              let minute = calendar["Minute"] as? Int
        else { return nil }
        return ScheduledTime(hour: hour, minute: minute)
    }

    private static func loadedTime(for action: ClockAction) -> ScheduledTime? {
        let result = Shell.run("/bin/launchctl", arguments: ["print", "\(guiDomain)/\(action.launchdLabel)"])
        guard result.status == 0 else { return nil }
        let hour = result.stdout.firstInteger(matching: #""Hour" => ([0-9]+)"#)
        let minute = result.stdout.firstInteger(matching: #""Minute" => ([0-9]+)"#)
        guard let hour, let minute else { return nil }
        return ScheduledTime(hour: hour, minute: minute)
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
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

// MARK: - Auto Punch

enum AutoPunchEngine {
    static func run(action: ClockAction) async -> Int32 {
        let config = ConfigManager.load()

        if FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) || !config.autopunchEnabled {
            AutoPunchLog.append("auto \(action.rawValue): skipped (disabled)")
            return 0
        }

        if await HolidayStore.isHoliday() {
            AutoPunchLog.append("auto \(action.rawValue): skipped (holiday)")
            return 0
        }

        guard let schedule = ScheduledTime(string: config.schedule.time(for: action)) else {
            AutoPunchLog.append("auto \(action.rawValue): FAILED — invalid schedule")
            SystemUI.notify(title: "104 Clock — Failed", body: "Invalid \(action.displayName) schedule.", sound: "Basso")
            return 1
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let scheduledDate = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: now) ?? now
        let minutesLate = now.timeIntervalSince(scheduledDate) / 60
        let wokeRecently = PowerStateMonitor.didWakeRecently()

        if wokeRecently {
            let choice = SystemUI.prompt(
                title: "104 Clock",
                message: "Your Mac just woke after the scheduled \(action.logLabel). Punch now?",
                buttons: ["Skip", "Punch"]
            )
            guard choice == "Punch" else {
                AutoPunchLog.append("auto \(action.rawValue): skipped by user (wake prompt)")
                SystemUI.notify(title: "104 Clock", body: "\(action.displayName) skipped.")
                return 0
            }
            AutoPunchLog.append("auto \(action.rawValue): user chose to punch (wake prompt)")
        } else if minutesLate > Double(config.lateThresholdMin) {
            let choice = SystemUI.prompt(
                title: "104 Clock",
                message: "Missed \(action.logLabel) at \(schedule.displayString). Punch now?",
                buttons: ["Skip", "Punch"]
            )
            guard choice == "Punch" else {
                AutoPunchLog.append("auto \(action.rawValue): skipped by user (late prompt)")
                SystemUI.notify(title: "104 Clock", body: "\(action.displayName) skipped.")
                return 0
            }
            AutoPunchLog.append("auto \(action.rawValue): user chose to punch (late)")
        } else {
            let delay = Int.random(in: 0...max(config.randomDelayMax, 0))
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }

        guard var session = AuthStore.loadSession(), session.hasUsableCookies else {
            let message = "Open ClockBar and sign in to 104 again."
            AutoPunchLog.append("auto \(action.rawValue): FAILED — missing session")
            SystemUI.notify(title: "104 Clock — Login Required", body: message, sound: "Basso")
            return 1
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)

            if action == .clockout, status.clockIn == nil {
                let message = "Cannot clock out because there is no clock-in record yet."
                AutoPunchLog.append("auto \(action.rawValue): skipped — \(message)")
                SystemUI.notify(title: "104 Clock", body: message)
                return 0
            }

            let existingPunchTime = existingPunch(for: action, in: status)
            if let existingPunchTime {
                AutoPunchLog.append("auto \(action.rawValue): already punched (\(action.fieldName)=\(existingPunchTime))")
                return 0
            }

            try await Clock104API.sendPunch(session: session)
            let verified = try await Clock104API.getStatus(session: session)
            if let punchTime = existingPunch(for: action, in: verified) {
                var message = "\(action == .clockin ? "Clocked in" : "Clocked out") at \(punchTime)"
                if action == .clockout, let clockIn = verified.clockIn {
                    message += " (in: \(clockIn))"
                }
                AutoPunchLog.append("auto \(action.rawValue): OK — \(message)")
                SystemUI.notify(title: "104 Clock", body: message)
                return 0
            }

            AutoPunchLog.append("auto \(action.rawValue): punch sent but not verified")
            SystemUI.notify(title: "104 Clock — Warning", body: "Punch sent but not verified.", sound: "Basso")
            return 1
        } catch Clock104Error.unauthorized {
            AuthStore.clear()
            AutoPunchLog.append("auto \(action.rawValue): FAILED — unauthorized")
            SystemUI.notify(title: "104 Clock — Login Required", body: "Your 104 session expired. Sign in again.", sound: "Basso")
            return 1
        } catch {
            AutoPunchLog.append("auto \(action.rawValue): FAILED — \(error.localizedDescription)")
            SystemUI.notify(title: "104 Clock — Failed", body: error.localizedDescription, sound: "Basso")
            return 1
        }
    }

    private static func existingPunch(for action: ClockAction, in status: PunchStatus) -> String? {
        switch action {
        case .clockin:
            return status.clockIn
        case .clockout:
            return status.clockOut
        }
    }
}

// MARK: - Wake Detection

enum PowerStateMonitor {
    static func didWakeRecently(window: TimeInterval = 600) -> Bool {
        let result = Shell.run("/usr/bin/pmset", arguments: ["-g", "log"])
        guard result.status == 0 else { return false }

        let cutoff = Date().addingTimeInterval(-window)
        let lines = result.stdout.split(separator: "\n").suffix(250)
        for line in lines.reversed() {
            let text = String(line)
            guard text.contains("lidopen") || text.contains("Wake ") || text.contains("DarkWake") else { continue }
            guard let date = DateFormatter.pmsetFormatter.date(from: String(text.prefix(25))) else { continue }
            return date >= cutoff
        }

        return false
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
