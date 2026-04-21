import Foundation

enum SystemUI {
    static func notify(title: String, body: String, sound: String = "default") {
        notifyViaApp(kind: "plain", title: title, body: body, sound: sound)
    }

    static func notifyMissedPunch(action: ClockAction, title: String, body: String) {
        notifyViaApp(
            kind: "missed_punch",
            title: title,
            body: body,
            sound: "default",
            extraQueryItems: [URLQueryItem(name: "action", value: action.rawValue)]
        )
    }

    private static func notifyViaApp(
        kind: String,
        title: String,
        body: String,
        sound: String,
        extraQueryItems: [URLQueryItem] = []
    ) {
        var components = URLComponents()
        components.scheme = "clockbar"
        components.host = "notify"
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "sound", value: sound),
        ] + extraQueryItems

        guard let url = components.url else { return }
        _ = Shell.run("/usr/bin/open", arguments: ["-g", url.absoluteString])
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
