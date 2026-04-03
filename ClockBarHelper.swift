import Foundation
import Darwin

@main
struct ClockBarHelper {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
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
            Darwin.exit(code)

        case "schedule":
            guard arguments.count >= 2 else {
                throw Clock104Error.api("Usage: clockbar-helper schedule install|remove|status")
            }

            switch arguments[1] {
            case "install":
                let config = ConfigManager.load()
                let state = try LaunchAgentManager.install(config: config)
                print(LaunchAgentManager.statusText(config: config))
                if let mismatch = state.mismatchSummary {
                    throw Clock104Error.scheduler(mismatch)
                }
            case "remove":
                try LaunchAgentManager.remove()
                print("Removed auto-punch launchd jobs.")
            case "status":
                print(LaunchAgentManager.statusText(config: ConfigManager.load()))
            default:
                throw Clock104Error.api("Usage: clockbar-helper schedule install|remove|status")
            }

        default:
            throw Clock104Error.api(helperUsage)
        }
    }

    private static let helperUsage = """
    Usage:
      clockbar-helper config
      clockbar-helper status
      clockbar-helper punch
      clockbar-helper auto clockin|clockout [--dry-run]
      clockbar-helper schedule install|remove|status
    """
}
