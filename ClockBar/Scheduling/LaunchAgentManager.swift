import Foundation

enum LaunchAgentManager {
    static func install(config: ClockConfig, helperExecutablePath: String? = nil) throws -> ScheduleState {
        let helperPath = helperExecutablePath ?? bundledHelperExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw Clock104Error.scheduler("Bundled helper is missing at \(helperPath).")
        }

        try FileManager.default.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        for action in ClockAction.allCases {
            let plistPath = plistPath(for: action)
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, plistPath.path])

            let plist = try generatePlist(
                action: action,
                config: config,
                helperExecutablePath: helperPath
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistPath, options: .atomic)

            let bootstrap = Shell.run(
                "/bin/launchctl",
                arguments: ["bootstrap", guiDomain, plistPath.path]
            )
            guard bootstrap.status == 0 else {
                throw Clock104Error.scheduler(
                    bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        let state = currentState(config: config)
        if let mismatch = state.mismatchSummary {
            throw Clock104Error.scheduler(mismatch)
        }
        return state
    }

    static func remove() throws {
        for action in ClockAction.allCases {
            let plist = plistPath(for: action)
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, plist.path])
            try? FileManager.default.removeItem(at: plist)
        }
    }

    static func currentState(config: ClockConfig) -> ScheduleState {
        let jobs = ClockAction.allCases.map { action -> ScheduleJobState in
            let configured = ScheduledTime(string: config.schedule.time(for: action))
            let installed = installedTime(for: action)
            let loaded = loadedTime(for: action)
            let isLoaded = loaded != nil

            let issue: String?
            if configured != installed {
                issue = "\(action.displayName) schedule differs from the installed plist."
            } else if installed != loaded {
                issue = "\(action.displayName) schedule differs from the loaded launchd trigger."
            } else if !isLoaded {
                issue = "\(action.displayName) launchd job is not loaded."
            } else {
                issue = nil
            }

            return ScheduleJobState(
                action: action,
                configuredTime: configured,
                installedTime: installed,
                loadedTime: loaded,
                isLoaded: isLoaded,
                issue: issue
            )
        }

        return ScheduleState(jobs: jobs, lastError: nil)
    }

    static func statusText(config: ClockConfig) -> String {
        let state = currentState(config: config)
        let lines = state.jobs.map { job -> String in
            let configured = job.configuredTime?.displayString ?? "--:--"
            let installed = job.installedTime?.displayString ?? "missing"
            let loaded = job.loadedTime?.displayString ?? "missing"
            let stateText = job.isLoaded ? "loaded" : "not loaded"
            return "  \(job.action.launchdLabel): \(stateText) config=\(configured) plist=\(installed) loaded=\(loaded)"
        }

        var output = ["=== launchd jobs ==="]
        output.append(contentsOf: lines)
        output.append("")
        output.append("=== auto-punch ===")
        output.append(
            "  \(config.autopunchEnabled && !FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) ? "enabled" : "DISABLED")"
        )
        output.append("")
        output.append("=== recent logs ===")
        if let data = try? String(contentsOf: autoPunchLogPath, encoding: .utf8) {
            output.append(contentsOf: data.split(separator: "\n").suffix(10).map { "  \($0)" })
        } else {
            output.append("  (no logs yet)")
        }

        return output.joined(separator: "\n")
    }

    private static func bundledHelperExecutablePath() -> String {
        let bundlePath = Bundle.main.bundlePath
        let candidate = (bundlePath as NSString).appendingPathComponent("Contents/MacOS/clockbar-helper")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return CommandLine.arguments[0]
    }

    private static func plistPath(for action: ClockAction) -> URL {
        launchAgentDirectory.appendingPathComponent("\(action.launchdLabel).plist")
    }

    private static func generatePlist(
        action: ClockAction,
        config: ClockConfig,
        helperExecutablePath: String
    ) throws -> [String: Any] {
        guard let time = ScheduledTime(string: config.schedule.time(for: action)) else {
            throw Clock104Error.scheduler("Invalid \(action.displayName) schedule.")
        }

        return [
            "Label": action.launchdLabel,
            "ProgramArguments": [helperExecutablePath, "auto", action.rawValue],
            "StartCalendarInterval": ["Hour": time.hour, "Minute": time.minute],
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "StandardOutPath": cacheDirectory
                .appendingPathComponent("launchd-\(action.rawValue).stdout.log").path,
            "StandardErrorPath": cacheDirectory
                .appendingPathComponent("launchd-\(action.rawValue).stderr.log").path,
        ]
    }

    private static func installedTime(for action: ClockAction) -> ScheduledTime? {
        let path = plistPath(for: action)
        guard let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let calendar = plist["StartCalendarInterval"] as? [String: Any],
              let hour = calendar["Hour"] as? Int,
              let minute = calendar["Minute"] as? Int
        else { return nil }

        return ScheduledTime(hour: hour, minute: minute)
    }

    private static func loadedTime(for action: ClockAction) -> ScheduledTime? {
        let result = Shell.run(
            "/bin/launchctl",
            arguments: ["print", "\(guiDomain)/\(action.launchdLabel)"]
        )
        guard result.status == 0 else { return nil }

        let hour = result.stdout.firstInteger(matching: #""Hour" => ([0-9]+)"#)
        let minute = result.stdout.firstInteger(matching: #""Minute" => ([0-9]+)"#)
        guard let hour, let minute else { return nil }

        return ScheduledTime(hour: hour, minute: minute)
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
    }
}
