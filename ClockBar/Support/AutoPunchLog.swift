import Foundation

enum AutoPunchLog {
    static func append(_ message: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let timestamp = DateFormatter.logTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
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
}
