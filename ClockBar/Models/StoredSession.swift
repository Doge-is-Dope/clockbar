import Foundation

struct StoredCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var isSecure: Bool
    var isHTTPOnly: Bool
    var expiresAt: Date?

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = (cookie.properties?[HTTPCookiePropertyKey("HttpOnly")] as? String) == "TRUE"
        self.expiresAt = cookie.expiresDate
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

struct StoredSession: Codable, Equatable {
    var cookies: [StoredCookie]
    var lastValidatedAt: Date?

    var cookieHeader: String {
        cookies
            .filter { !$0.isExpired }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    var hasUsableCookies: Bool {
        !cookieHeader.isEmpty
    }
}
