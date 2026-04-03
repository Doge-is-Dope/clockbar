import Foundation
import Security

enum AuthStore {
    private static let service = "com.clockbar.104.clockbar.session"
    private static let account = "default"

    static func loadSession() -> StoredSession? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return nil
        }

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
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
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
