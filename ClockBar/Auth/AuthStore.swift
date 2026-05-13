import Foundation

enum AuthStore {
    static func loadSession() -> StoredSession? {
        if isRunningInSwiftUIPreviews { return nil }

        guard let data = try? Data(contentsOf: sessionPath),
            let session = try? JSONDecoder.clockStore.decode(StoredSession.self, from: data)
        else { return nil }

        return session
    }

    static func save(_ session: StoredSession) throws {
        var pruned = session
        pruned.cookies = pruned.cookies.filter { !$0.isExpired }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.clockStore.encode(pruned)
        try data.write(to: sessionPath, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: sessionPath.path
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: sessionPath)
    }
}
