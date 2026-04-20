import Foundation

enum LogLevel: String {
    case info  = "INFO "
    case warn  = "WARN "
    case error = "ERROR"
}

enum AutoPunchLog {
    static func info(
        _ component: String,
        _ event: String,
        _ fields: KeyValuePairs<String, CustomStringConvertible> = [:]
    ) {
        write(.info, component, event, fields)
    }

    static func warn(
        _ component: String,
        _ event: String,
        _ fields: KeyValuePairs<String, CustomStringConvertible> = [:]
    ) {
        write(.warn, component, event, fields)
    }

    static func error(
        _ component: String,
        _ event: String,
        _ fields: KeyValuePairs<String, CustomStringConvertible> = [:]
    ) {
        write(.error, component, event, fields)
    }

    private static func write(
        _ level: LogLevel,
        _ component: String,
        _ event: String,
        _ fields: KeyValuePairs<String, CustomStringConvertible>
    ) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let timestamp = DateFormatter.logTimestampFormatter.string(from: Date())
        var line = "[\(timestamp)] [\(level.rawValue)] \(component): \(event)"
        for (key, value) in fields {
            line += " \(key)=\(formatValue(value.description))"
        }
        line += "\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: autoPunchLogPath.path),
           let handle = try? FileHandle(forWritingTo: autoPunchLogPath) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }

        try? data.write(to: autoPunchLogPath, options: .atomic)
    }

    private static func formatValue(_ value: String) -> String {
        if value.isEmpty || value.contains(where: { $0.isWhitespace || $0 == "=" || $0 == "\"" }) {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
