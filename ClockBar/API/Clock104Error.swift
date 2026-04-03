import Foundation

enum Clock104Error: LocalizedError {
    case missingSession
    case unauthorized
    case invalidResponse(String)
    case api(String)
    case keychain(String)
    case scheduler(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Sign in to 104 to continue."
        case .unauthorized:
            return "Your 104 session expired. Sign in again."
        case .invalidResponse(let message), .api(let message), .keychain(let message), .scheduler(let message):
            return message
        }
    }
}
