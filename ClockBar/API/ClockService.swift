import Foundation

enum ClockService {
    static func getStatus() async -> PunchStatus {
        guard var session = AuthStore.loadSession() else {
            return .error("Sign in to 104 to enable status and punching.")
        }

        do {
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)
            return status
        } catch Clock104Error.unauthorized {
            return .error(Clock104Error.unauthorized.localizedDescription)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func punch() async -> PunchStatus {
        Log.info("manual", "invoked")

        guard var session = AuthStore.loadSession() else {
            Log.error("manual", "failed", ["reason": "missing_session"])
            return .error("Sign in to 104 before punching.")
        }

        do {
            try await Clock104API.sendPunch(session: session)
            let status = try await Clock104API.getStatus(session: session)
            session.lastValidatedAt = Date()
            try? AuthStore.save(session)
            if let clockIn = status.clockIn, status.clockOut == nil {
                Log.info("manual", "completed", ["action": "clockin", "punched_at": clockIn])
            } else if let clockOut = status.clockOut {
                Log.info("manual", "completed", ["action": "clockout", "punched_at": clockOut])
            } else {
                Log.warn("manual", "verification_pending")
            }
            return status
        } catch Clock104Error.unauthorized {
            Log.error("manual", "failed", ["reason": "unauthorized"])
            return .error(Clock104Error.unauthorized.localizedDescription)
        } catch {
            Log.error(
                "manual", "failed",
                [
                    "reason": "exception",
                    "error_message": error.localizedDescription,
                ])
            return .error(error.localizedDescription)
        }
    }

    static func createStoredSession(from cookies: [HTTPCookie]) async throws -> StoredSession {
        let relevantCookies = cookies.filter { $0.domain.contains("104") }
        guard !relevantCookies.isEmpty else {
            throw Clock104Error.missingSession
        }

        return try await Clock104API.validate(
            session: StoredSession(
                cookies: relevantCookies.map(StoredCookie.init(cookie:)),
                lastValidatedAt: nil
            )
        )
    }

    static func saveSession(_ session: StoredSession) throws {
        try AuthStore.save(session)
    }

    static func clearSession() {
        AuthStore.clear()
    }

    static func syncSchedule(config: ClockConfig) throws -> ScheduleState {
        if config.requiresScheduledJobs {
            return try LaunchAgentManager.install(config: config)
        }

        try LaunchAgentManager.remove()
        return LaunchAgentManager.currentState(config: config)
    }

    static func currentScheduleState(config: ClockConfig) -> ScheduleState {
        LaunchAgentManager.currentState(config: config)
    }
}
