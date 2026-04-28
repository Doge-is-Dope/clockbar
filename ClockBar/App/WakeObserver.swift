import AppKit
import Foundation

@MainActor
final class WakeObserver {
    private let coordinator: PunchReminderCoordinator
    private var observers: [NSObjectProtocol] = []

    init(coordinator: PunchReminderCoordinator) {
        self.coordinator = coordinator
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.coordinator.checkPending(reason: name.rawValue)
                }
            }
            observers.append(token)
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
        }
    }
}
