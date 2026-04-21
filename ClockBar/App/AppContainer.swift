import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let viewModel: StatusViewModel
    let appUpdater: AppUpdater
    let settingsController: SettingsWindowController

    init() {
        let model = StatusViewModel()
        let updater = AppUpdater()
        self.viewModel = model
        self.appUpdater = updater
        self.settingsController = SettingsWindowController(viewModel: model, appUpdater: updater)
        NotificationManager.shared.punchHandler = { [weak model] in
            Task { @MainActor in model?.punchNow() }
        }
        model.start()
    }
}
