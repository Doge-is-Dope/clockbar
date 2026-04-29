import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let viewModel: StatusViewModel
    let appUpdater: AppUpdater
    let settingsController: SettingsWindowController
    let reminderCoordinator: PunchReminderCoordinator
    private let wakeObserver: WakeObserver
    private var sessionRefreshToken: SessionRefreshSignal.Token?

    init() {
        let model = StatusViewModel()
        let updater = AppUpdater()
        let coordinator = PunchReminderCoordinator()
        self.viewModel = model
        self.appUpdater = updater
        self.settingsController = SettingsWindowController(viewModel: model, appUpdater: updater)
        self.reminderCoordinator = coordinator
        self.wakeObserver = WakeObserver(viewModel: model, coordinator: coordinator)
        NotificationManager.shared.punchHandler = { [weak model] in
            Task { @MainActor in model?.punchNow() }
        }
        self.sessionRefreshToken = SessionRefreshSignal.subscribe { [weak model] in
            Task { @MainActor in model?.recoverSessionIfNeeded(trigger: "distributed_signal") }
        }
        model.start()
        coordinator.checkPending(reason: "app_launch")
    }
}
