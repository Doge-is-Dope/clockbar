import Foundation

@MainActor
final class NotificationLedger {
    static let shared = NotificationLedger()

    private struct Entry: Codable {
        let kind: String
        let action: String
        let date: String
        let recordedAt: Date
    }

    private let url = cacheDirectory.appendingPathComponent("notification-ledger.json")
    private var entries: [Entry] = []

    private init() {
        load()
    }

    func hasFired(kind: PunchNotificationKind, action: ClockAction, date: String) -> Bool {
        entries.contains { $0.kind == kind.rawValue && $0.action == action.rawValue && $0.date == date }
    }

    func record(kind: PunchNotificationKind, action: ClockAction, date: String) {
        guard !hasFired(kind: kind, action: action, date: date) else { return }
        entries.append(Entry(
            kind: kind.rawValue,
            action: action.rawValue,
            date: date,
            recordedAt: Date()
        ))
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.iso8601.decode([Entry].self, from: data) else {
            entries = []
            return
        }
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        entries = decoded.filter { $0.recordedAt >= cutoff }
        if entries.count != decoded.count {
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.iso8601.encode(entries) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
