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
        case "status":
            let status = await ClockService.getStatus()
            let data = try JSONEncoder.clockStore.encode(status)
            print(String(decoding: data, as: UTF8.self))

        case "punch":
            let status = await ClockService.punch()
            let data = try JSONEncoder.clockStore.encode(status)
            print(String(decoding: data, as: UTF8.self))

        case "auto":
            guard arguments.count >= 2, let action = ClockAction(rawValue: arguments[1]) else {
                throw Clock104Error.api("Usage: clockbar-helper auto clockin|clockout")
            }
            let code = await AutoPunchEngine.run(action: action)
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
      clockbar-helper status
      clockbar-helper punch
      clockbar-helper auto clockin|clockout
      clockbar-helper schedule install|remove|status
    """
}
