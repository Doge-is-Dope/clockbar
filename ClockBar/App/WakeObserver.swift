import AppKit
import Foundation

@MainActor
final class WakeObserver {
    private let viewModel: StatusViewModel
    private let coordinator: PunchReminderCoordinator
    private var observers: [NSObjectProtocol] = []

    init(viewModel: StatusViewModel, coordinator: PunchReminderCoordinator) {
        self.viewModel = viewModel
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
                    self?.handleWake(reason: name.rawValue)
                }
            }
            observers.append(token)
        }
    }

    private func handleWake(reason: String) {
        viewModel.refresh()
        coordinator.checkPending(reason: reason)
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
        }
    }
}
