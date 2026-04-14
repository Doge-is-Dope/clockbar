import Foundation

enum LaunchAgentManager {
    private struct LaunchJobSpec {
        let label: String
        let plistPath: URL
        let time: ScheduledTime
        let programArguments: [String]
        let stdoutPath: URL
        let stderrPath: URL
    }

    // MARK: - Production

    static func install(config: ClockConfig, helperExecutablePath: String? = nil) throws -> ScheduleState {
        guard config.requiresScheduledJobs else {
            try remove()
            return currentState(config: config)
        }

        let helperPath = try resolveHelperPath(helperExecutablePath)
        let specs = try productionSpecs(config: config, helperPath: helperPath)
        try installSpecs(specs)

        let state = currentState(config: config)
        if let mismatch = state.mismatchSummary {
            throw Clock104Error.scheduler(mismatch)
        }
        return state
    }

    static func remove() throws {
        var errors: [String] = []
        for action in ClockAction.allCases {
            let plist = productionPlistPath(for: action)
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, plist.path])
            do {
                try FileManager.default.removeItem(at: plist)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {
                // Already gone — fine
            } catch {
                errors.append("\(action): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty {
            throw Clock104Error.scheduler("Failed to remove agents: \(errors.joined(separator: "; "))")
        }
    }

    static var hasInstalledPlists: Bool {
        ClockAction.allCases.contains { action in
            FileManager.default.fileExists(atPath: productionPlistPath(for: action).path)
        }
    }

    static func currentState(config: ClockConfig) -> ScheduleState {
        guard config.requiresScheduledJobs else {
            return ScheduleState(jobs: [], lastError: nil)
        }

        let jobs = ClockAction.allCases.map { action -> ScheduleJobState in
            let configured = ScheduledTime(string: config.schedule.time(for: action))
            let installed = installedTime(at: productionPlistPath(for: action))
            let loaded = loadedTime(forLabel: action.launchdLabel)
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
        if config.requiresScheduledJobs {
            output.append(contentsOf: lines)
        } else {
            output.append("  disabled")
        }
        output.append("")
        output.append("=== auto-punch ===")
        output.append(
            "  \(config.requiresScheduledJobs && !FileManager.default.fileExists(atPath: autoPunchKillSwitchPath.path) ? "enabled" : "DISABLED")"
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

    // MARK: - Test surface

    static func installTest(
        action: ClockAction,
        time: ScheduledTime,
        realPunch: Bool = false,
        helperExecutablePath: String? = nil
    ) throws {
        guard (0...23).contains(time.hour), (0...59).contains(time.minute) else {
            throw Clock104Error.scheduler(
                "Invalid time \(time.displayString): hour must be 0-23, minute must be 0-59."
            )
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        if let target = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now),
           target.timeIntervalSince(now) < 60 {
            throw Clock104Error.scheduler(
                "Time \(time.displayString) is within the next 60s or already passed — launchd may skip today's fire or not fire until tomorrow. Pick a time at least 1 minute in the future."
            )
        }

        let helperPath = try resolveHelperPath(helperExecutablePath)
        let spec = testSpec(action: action, time: time, helperPath: helperPath, realPunch: realPunch)
        try installSpecs([spec])

        AutoPunchLog.append(
            "schedule test: installed \(spec.label) for \(time.displayString) dryRun=\(!realPunch)"
        )
    }

    static func removeTest(action: ClockAction? = nil) throws {
        let actions: [ClockAction] = action.map { [$0] } ?? ClockAction.allCases
        var errors: [String] = []

        for target in actions {
            let path = testPlistPath(for: target)
            _ = Shell.run(
                "/bin/launchctl",
                arguments: ["bootout", guiDomain, path.path]
            )
            do {
                try FileManager.default.removeItem(at: path)
                AutoPunchLog.append("schedule test: removed \(testLabel(for: target))")
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {
                // Already gone — fine
            } catch {
                errors.append("\(target): \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            throw Clock104Error.scheduler("Failed to remove test agents: \(errors.joined(separator: "; "))")
        }
    }

    static func testStatus() -> String {
        var output = ["=== test launchd jobs ==="]
        var anyInstalled = false

        for action in ClockAction.allCases {
            let label = testLabel(for: action)
            let path = testPlistPath(for: action)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            anyInstalled = true

            let installed = installedTime(at: path)?.displayString ?? "(unreadable)"
            let loaded = loadedTime(forLabel: label)?.displayString ?? "not loaded"
            let args = installedProgramArguments(at: path)?.joined(separator: " ") ?? "(unreadable)"

            output.append("  \(label):")
            output.append("    plist=\(path.path)")
            output.append("    time=\(installed) loaded=\(loaded)")
            output.append("    args=\(args)")
            output.append("    stdout=\(testStdoutPath(for: action).path)")
            output.append("    stderr=\(testStderrPath(for: action).path)")
        }

        if !anyInstalled {
            output.append("  (none installed)")
        } else {
            output.append("")
            output.append("Remove with: clockbar-helper schedule test remove [clockin|clockout]")
            output.append("Live log:    tail -f \(autoPunchLogPath.path)")
        }
        return output.joined(separator: "\n")
    }

    // MARK: - Spec construction

    private static func productionSpecs(
        config: ClockConfig,
        helperPath: String
    ) throws -> [LaunchJobSpec] {
        try ClockAction.allCases.map { action in
            guard let time = ScheduledTime(string: config.schedule.time(for: action)) else {
                throw Clock104Error.scheduler("Invalid \(action.displayName) schedule.")
            }
            return LaunchJobSpec(
                label: action.launchdLabel,
                plistPath: productionPlistPath(for: action),
                time: time,
                programArguments: [helperPath, "auto", action.rawValue],
                stdoutPath: cacheDirectory
                    .appendingPathComponent("launchd-\(action.rawValue).stdout.log"),
                stderrPath: cacheDirectory
                    .appendingPathComponent("launchd-\(action.rawValue).stderr.log")
            )
        }
    }

    private static func testSpec(
        action: ClockAction,
        time: ScheduledTime,
        helperPath: String,
        realPunch: Bool
    ) -> LaunchJobSpec {
        var args = [helperPath, "auto", action.rawValue]
        if !realPunch {
            args.append("--dry-run")
        }
        return LaunchJobSpec(
            label: testLabel(for: action),
            plistPath: testPlistPath(for: action),
            time: time,
            programArguments: args,
            stdoutPath: testStdoutPath(for: action),
            stderrPath: testStderrPath(for: action)
        )
    }

    // MARK: - Bootstrap primitive

    private static func installSpecs(_ specs: [LaunchJobSpec]) throws {
        try FileManager.default.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        for spec in specs {
            _ = Shell.run("/bin/launchctl", arguments: ["bootout", guiDomain, spec.plistPath.path])

            let plist = generatePlist(spec: spec)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: spec.plistPath, options: .atomic)

            let bootstrap = Shell.run(
                "/bin/launchctl",
                arguments: ["bootstrap", guiDomain, spec.plistPath.path]
            )
            guard bootstrap.status == 0 else {
                throw Clock104Error.scheduler(
                    bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
    }

    private static func generatePlist(spec: LaunchJobSpec) -> [String: Any] {
        [
            "Label": spec.label,
            "ProgramArguments": spec.programArguments,
            "StartCalendarInterval": ["Hour": spec.time.hour, "Minute": spec.time.minute],
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "StandardOutPath": spec.stdoutPath.path,
            "StandardErrorPath": spec.stderrPath.path,
        ]
    }

    // MARK: - Path helpers

    private static func productionPlistPath(for action: ClockAction) -> URL {
        launchAgentDirectory.appendingPathComponent("\(action.launchdLabel).plist")
    }

    private static func testLabel(for action: ClockAction) -> String {
        "\(launchdLabelPrefix)test-\(action.rawValue)"
    }

    private static func testPlistPath(for action: ClockAction) -> URL {
        launchAgentDirectory.appendingPathComponent("\(testLabel(for: action)).plist")
    }

    private static func testStdoutPath(for action: ClockAction) -> URL {
        cacheDirectory.appendingPathComponent("launchd-test-\(action.rawValue).stdout.log")
    }

    private static func testStderrPath(for action: ClockAction) -> URL {
        cacheDirectory.appendingPathComponent("launchd-test-\(action.rawValue).stderr.log")
    }

    private static func resolveHelperPath(_ override: String?) throws -> String {
        let helperPath = override ?? bundledHelperExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw Clock104Error.scheduler("Bundled helper is missing at \(helperPath).")
        }
        return helperPath
    }

    private static func bundledHelperExecutablePath() -> String {
        let bundlePath = Bundle.main.bundlePath
        let candidate = (bundlePath as NSString).appendingPathComponent("Contents/MacOS/clockbar-helper")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return CommandLine.arguments[0]
    }

    private static func installedTime(at path: URL) -> ScheduledTime? {
        guard let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let calendar = plist["StartCalendarInterval"] as? [String: Any],
              let hour = calendar["Hour"] as? Int,
              let minute = calendar["Minute"] as? Int
        else { return nil }

        return ScheduledTime(hour: hour, minute: minute)
    }

    private static func installedProgramArguments(at path: URL) -> [String]? {
        guard let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String]
        else { return nil }
        return args
    }

    private static func loadedTime(forLabel label: String) -> ScheduledTime? {
        let result = Shell.run(
            "/bin/launchctl",
            arguments: ["print", "\(guiDomain)/\(label)"]
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
