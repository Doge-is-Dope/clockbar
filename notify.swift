import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let args = CommandLine.arguments

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard args.count >= 3 else {
            fputs("Usage: notify <title> <message> [sound]\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                fputs("Notification permission denied. Enable in System Settings > Notifications > 104 Clock.\n", stderr)
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return
            }
            self.sendNotification()
        }
    }

    func sendNotification() {
        let title = args[1]
        let message = args[2]
        let soundName = args.count > 3 ? args[3] : "default"

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = soundName == "default"
            ? .default
            : UNNotificationSound(named: UNNotificationSoundName(soundName))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                fputs("Error: \(error.localizedDescription)\n", stderr)
            }
            // Brief delay to ensure notification is delivered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
