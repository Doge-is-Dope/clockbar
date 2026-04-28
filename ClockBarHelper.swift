import Foundation
import Darwin

@main
struct ClockBarHelper {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            let argv = CommandLine.arguments.dropFirst().joined(separator: " ")
            Log.error("helper", "failed", [
                "reason": "uncaught_exception",
                "argv": argv,
                "error_message": error.localizedDescription,
            ])
            fputs("\(error.localizedDescription)\n", stderr)
            Darwin.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw Clock104Error.api(helperUsage)
        }

        switch command {
        case "config":
            let config = ConfigManager.load()
            let data = try JSONEncoder.clockStore.encode(config)
            print(String(decoding: data, as: UTF8.self))

        case "status":
            let status = await ClockService.getStatus()
            let data = try JSONEncoder.clockStore.encode(status)
            print(String(decoding: data, as: UTF8.self))

        case "punch":
            let status = await ClockService.punch()
            let data = try JSONEncoder.clockStore.encode(status)
            print(String(decoding: data, as: UTF8.self))

        case "auto":
            let dryRun = arguments.contains("--dry-run")
            let actionArguments = arguments.dropFirst().filter { $0 != "--dry-run" }
            guard let actionArgument = actionArguments.first,
                  actionArguments.count == 1,
                  let action = ClockAction(rawValue: actionArgument) else {
                throw Clock104Error.api("Usage: clockbar-helper auto clockin|clockout [--dry-run]")
            }
            let code = await AutoPunchEngine.run(action: action, dryRun: dryRun)
            if code != 0 {
                Log.info("auto.\(action.rawValue)", "exit", ["code": code])
            }
            Darwin.exit(code)

        case "schedule":
            guard arguments.count >= 2 else {
                throw Clock104Error.api(scheduleUsage)
            }

            let scheduleRest = Array(arguments.dropFirst(2))
            let force = scheduleRest.contains("--force")

            switch arguments[1] {
            case "install":
                let config = ConfigManager.load()
                let state = try LaunchAgentManager.install(config: config, force: force)
                print(LaunchAgentManager.statusText(config: config))
                if let mismatch = state.mismatchSummary {
                    throw Clock104Error.scheduler(mismatch)
                }
            case "remove":
                try LaunchAgentManager.remove(force: force)
                print("Removed auto-punch launchd jobs.")
            case "status":
                print(LaunchAgentManager.statusText(config: ConfigManager.load()))
            case "test":
                try handleScheduleTest(arguments: Array(arguments.dropFirst(2)))
            default:
                throw Clock104Error.api(scheduleUsage)
            }

        default:
            throw Clock104Error.api(helperUsage)
        }
    }

    private static func handleScheduleTest(arguments: [String]) throws {
        guard let sub = arguments.first else {
            throw Clock104Error.api(scheduleTestUsage)
        }

        switch sub {
        case "install":
            let rest = Array(arguments.dropFirst())
            let realPunch = rest.contains("--real")
            let force = rest.contains("--force")
            let positional = rest.filter { $0 != "--real" && $0 != "--force" }
            guard positional.count == 2,
                  let action = ClockAction(rawValue: positional[0]),
                  let time = ScheduledTime(string: positional[1]) else {
                throw Clock104Error.api(scheduleTestUsage)
            }

            if realPunch {
                fputs(
                    "WARNING: --real will hit the 104 API and create a real \(action.logLabel) record at \(time.displayString).\n",
                    stderr
                )
            }

            try LaunchAgentManager.installTest(
                action: action,
                time: time,
                realPunch: realPunch,
                force: force
            )
            print("Installed test job for \(action.rawValue) at \(time.displayString) (dryRun=\(!realPunch)).")
            print(LaunchAgentManager.testStatus())

        case "status":
            print(LaunchAgentManager.testStatus())

        case "remove":
            let rest = Array(arguments.dropFirst())
            let force = rest.contains("--force")
            let positional = rest.filter { $0 != "--force" }
            let action = positional.first.flatMap { ClockAction(rawValue: $0) }
            if !positional.isEmpty && action == nil {
                throw Clock104Error.api(scheduleTestUsage)
            }
            try LaunchAgentManager.removeTest(action: action, force: force)
            print("Removed test job(s).")

        default:
            throw Clock104Error.api(scheduleTestUsage)
        }
    }

    private static let scheduleUsage = """
    Usage: clockbar-helper schedule install|status [--force]
           clockbar-helper schedule remove [--force]
           clockbar-helper schedule test install <clockin|clockout> <HH:MM> [--real] [--force]
           clockbar-helper schedule test status
           clockbar-helper schedule test remove [<clockin|clockout>] [--force]

    --force interrupts any in-flight auto-punch instead of waiting for it.
    """

    private static let scheduleTestUsage = """
    Usage: clockbar-helper schedule test install <clockin|clockout> <HH:MM> [--real] [--force]
           clockbar-helper schedule test status
           clockbar-helper schedule test remove [<clockin|clockout>] [--force]

    --force interrupts any in-flight auto-punch instead of waiting for it.
    """

    private static let helperUsage = """
    Usage:
      clockbar-helper config
      clockbar-helper status
      clockbar-helper punch
      clockbar-helper auto clockin|clockout [--dry-run]
      clockbar-helper schedule install|remove|status [--force]
      clockbar-helper schedule test install|status|remove ... [--force]
    """
}
