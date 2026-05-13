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
        hasFired(kind: kind, key: action.rawValue, date: date)
    }

    func record(kind: PunchNotificationKind, action: ClockAction, date: String) {
        record(kind: kind, key: action.rawValue, date: date)
    }

    /// Generic-key variant — e.g. the re-login warning keys on the OIDC expiry
    /// date so it fires once per cookie cycle.
    func hasFired(kind: PunchNotificationKind, key: String, date: String) -> Bool {
        entries.contains { $0.kind == kind.rawValue && $0.action == key && $0.date == date }
    }

    func record(kind: PunchNotificationKind, key: String, date: String) {
        guard !hasFired(kind: kind, key: key, date: date) else { return }
        entries.append(
            Entry(
                kind: kind.rawValue,
                action: key,
                date: date,
                recordedAt: Date()
            ))
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder.iso8601.decode([Entry].self, from: data)
        else {
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

extension JSONDecoder {
    fileprivate static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    fileprivate static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
