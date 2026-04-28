import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let punchNowActionIdentifier = "punchNow"

    var punchHandler: (() -> Void)?

    private var didSetup = false

    func setup() {
        guard !didSetup else { return }

        didSetup = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let punchAction = UNNotificationAction(
            identifier: Self.punchNowActionIdentifier,
            title: "Punch Now",
            options: [.foreground]
        )
        let categories = PunchNotificationKind.allCases.map { kind in
            UNNotificationCategory(
                identifier: kind.categoryIdentifier,
                actions: kind.hasPunchAction ? [punchAction] : [],
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(categories))

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(
        _ title: String,
        body: String,
        sound: UNNotificationSound = .default,
        categoryIdentifier: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "clockbar",
              url.host == "notify",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first(where: { $0.name == name })?.value
        }

        let title = value("title") ?? appName
        let body = value("body") ?? ""
        let kind = value("kind") ?? "plain"
        let soundName = value("sound") ?? "default"

        let sound: UNNotificationSound = (soundName == "default")
            ? .default
            : UNNotificationSound(named: UNNotificationSoundName(soundName))

        let categoryIdentifier = PunchNotificationKind(rawValue: kind)?.categoryIdentifier

        send(title, body: body, sound: sound, categoryIdentifier: categoryIdentifier)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        defer { handler() }
        if response.actionIdentifier == Self.punchNowActionIdentifier {
            DispatchQueue.main.async { [weak self] in
                self?.punchHandler?()
            }
        }
    }
}
