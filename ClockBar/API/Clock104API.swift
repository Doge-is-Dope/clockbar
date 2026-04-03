import Foundation

enum Clock104API {
    static func validate(session: StoredSession) async throws -> StoredSession {
        _ = try await getStatus(session: session)
        var updated = session
        updated.lastValidatedAt = Date()
        return updated
    }

    static func getStatus(session: StoredSession) async throws -> PunchStatus {
        guard session.hasUsableCookies else { throw Clock104Error.missingSession }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayRange = calendar.range(of: .day, in: .month, for: now) ?? 1..<32
        var endComponents = calendar.dateComponents([.year, .month], from: now)
        endComponents.day = dayRange.count
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59
        let endOfMonth = calendar.date(from: endComponents) ?? now

        let json = try await requestJSON(
            path: "/psc2/api/home/newCalendar/\(Int(startOfMonth.timeIntervalSince1970 * 1000))/\(Int(endOfMonth.timeIntervalSince1970 * 1000))",
            method: "GET",
            session: session
        )

        if (json["code"] as? Int) == 401 {
            throw Clock104Error.unauthorized
        }

        guard let entries = json["data"] as? [[String: Any]] else {
            throw Clock104Error.invalidResponse("Unable to parse attendance status.")
        }

        let today = calendar.startOfDay(for: now)
        for entry in entries {
            guard let dateMilliseconds = entry["date"] as? Double ?? (entry["date"] as? Int).map(Double.init) else {
                continue
            }

            let entryDate = calendar.startOfDay(
                for: Date(timeIntervalSince1970: dateMilliseconds / 1000)
            )
            guard entryDate == today else { continue }

            let clockInfo = entry["clockIn"] as? [String: Any] ?? [:]
            return PunchStatus(
                date: DateFormatter.statusDateFormatter.string(from: now),
                clockIn: formatTimestamp(clockInfo["start"]),
                clockOut: formatTimestamp(clockInfo["end"]),
                clockInCode: clockInfo["clockInCode"] as? Int,
                error: nil
            )
        }

        return PunchStatus(
            date: DateFormatter.statusDateFormatter.string(from: now),
            clockIn: nil,
            clockOut: nil,
            clockInCode: nil,
            error: nil
        )
    }

    static func sendPunch(session: StoredSession) async throws {
        guard session.hasUsableCookies else { throw Clock104Error.missingSession }

        let json = try await requestJSON(
            path: "/psc2/api/f0400/newClockin",
            method: "POST",
            session: session
        )

        if (json["code"] as? Int) == 401 {
            throw Clock104Error.unauthorized
        }

        if let code = json["code"] as? Int, code != 200 {
            let message = json["message"] as? String ?? "Punch failed."
            throw Clock104Error.api(message)
        }
    }

    private static func requestJSON(
        path: String,
        method: String,
        session: StoredSession
    ) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("JSON", forHTTPHeaderField: "X-Request")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")

        if method == "POST" {
            request.httpBody = Data()
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Clock104Error.invalidResponse("No HTTP response from 104.")
        }

        if httpResponse.statusCode == 401 {
            throw Clock104Error.unauthorized
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Clock104Error.invalidResponse("104 returned malformed JSON.")
        }

        return json
    }

    private static func formatTimestamp(_ value: Any?) -> String? {
        guard let milliseconds = value as? Double ?? (value as? Int).map(Double.init) else { return nil }
        return DateFormatter.shortTimeFormatter.string(
            from: Date(timeIntervalSince1970: milliseconds / 1000)
        )
    }
}
