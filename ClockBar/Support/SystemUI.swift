import Foundation

enum SystemUI {
    static func notify(title: String, body: String, sound: String = "default") {
        let script = """
        display notification "\(escapeAppleScript(body))" with title "\(escapeAppleScript(title))" sound name "\(escapeAppleScript(sound))"
        """
        _ = Shell.run("/usr/bin/osascript", arguments: ["-e", script])
    }

    static func prompt(title: String, message: String, buttons: [String]) -> String? {
        let buttonList = buttons.map { "\"\(escapeAppleScript($0))\"" }.joined(separator: ", ")
        let script = """
        display dialog "\(escapeAppleScript(message))" with title "\(escapeAppleScript(title))" buttons {\(buttonList)} default button "\(escapeAppleScript(buttons.last ?? "OK"))"
        """
        let result = Shell.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.status == 0 else { return nil }

        for part in result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",") {
            let text = String(part)
            if text.contains("button returned:") {
                return text.split(separator: ":", maxSplits: 1).last.map(String.init)
            }
        }

        return nil
    }

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
