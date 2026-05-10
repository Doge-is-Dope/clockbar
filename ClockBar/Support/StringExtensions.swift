import Foundation

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func firstInteger(matching pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
            let range = Range(match.range(at: 1), in: self)
        else { return nil }

        return Int(self[range])
    }
}
