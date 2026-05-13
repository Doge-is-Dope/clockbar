import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let viewModel: StatusViewModel
    let settingsController: SettingsWindowController
    let reminderCoordinator: PunchReminderCoordinator
    private let wakeObserver: WakeObserver
    private var sessionRefreshToken: SessionRefreshSignal.Token?

    init() {
        let model = StatusViewModel()
        let coordinator = PunchReminderCoordinator()
        self.viewModel = model
        self.settingsController = SettingsWindowController(viewModel: model)
        self.reminderCoordinator = coordinator
        self.wakeObserver = WakeObserver(viewModel: model, coordinator: coordinator)
        NotificationManager.shared.punchHandler = { [weak model] in
            Task { @MainActor in model?.punchNow() }
        }
        NotificationManager.shared.signInHandler = { [weak model] in
            Task { @MainActor in model?.beginAuthentication() }
        }
        self.sessionRefreshToken = SessionRefreshSignal.subscribe { [weak model] in
            Task { @MainActor in
                guard let model else { return }
                let recovered = await model.forceSessionRecovery(trigger: "distributed_signal")
                if recovered {
                    model.refresh()
                }
            }
        }
        model.start()
        coordinator.checkPending(reason: "app_launch")
    }
}
