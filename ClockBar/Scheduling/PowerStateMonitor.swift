import Foundation

enum PowerStateMonitor {
    enum WakeKind: String {
        case lidopen
        case darkWake = "DarkWake"
        case wake = "Wake"
    }

    struct WakeEvent {
        let date: Date
        let kind: WakeKind
    }

    static func recentWake(window: TimeInterval = 600) -> WakeEvent? {
        let result = Shell.run("/usr/bin/pmset", arguments: ["-g", "log"])
        guard result.status == 0 else { return nil }

        let cutoff = Date().addingTimeInterval(-window)
        let lines = result.stdout.split(separator: "\n").suffix(250)
        for line in lines.reversed() {
            let text = String(line)
            let kind: WakeKind
            if text.contains("lidopen") {
                kind = .lidopen
            } else if text.contains("DarkWake") {
                kind = .darkWake
            } else if text.contains("Wake ") {
                kind = .wake
            } else {
                continue
            }
            guard let date = DateFormatter.pmsetFormatter.date(from: String(text.prefix(25))) else {
                continue
            }
            guard date >= cutoff else { return nil }
            return WakeEvent(date: date, kind: kind)
        }

        return nil
    }
}
