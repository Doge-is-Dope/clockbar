import Foundation
import UserNotifications

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
