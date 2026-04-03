import Foundation

enum PowerStateMonitor {
    static func didWakeRecently(window: TimeInterval = 600) -> Bool {
        let result = Shell.run("/usr/bin/pmset", arguments: ["-g", "log"])
        guard result.status == 0 else { return false }

        let cutoff = Date().addingTimeInterval(-window)
        let lines = result.stdout.split(separator: "\n").suffix(250)
        for line in lines.reversed() {
            let text = String(line)
            guard text.contains("lidopen") || text.contains("Wake ") || text.contains("DarkWake") else {
                continue
            }
            guard let date = DateFormatter.pmsetFormatter.date(from: String(text.prefix(25))) else {
                continue
            }
            return date >= cutoff
        }

        return false
    }
}
