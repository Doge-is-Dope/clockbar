import Foundation

enum SystemUI {
    static func notify(title: String, body: String, sound: String = "default") {
        notifyViaApp(kind: "plain", title: title, body: body, sound: sound)
    }

    static func notifyMissedPunch(action: ClockAction, title: String, body: String) {
        notifyViaApp(
            kind: PunchNotificationKind.missed.rawValue,
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
}
