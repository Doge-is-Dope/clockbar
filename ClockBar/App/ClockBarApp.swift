import AppKit
import SwiftUI

@main
@MainActor
struct ClockBarApp: App {
    @StateObject private var viewModel: StatusViewModel
    private let appUpdater: AppUpdater
    private let settingsController: SettingsWindowController

    init() {
        NotificationManager.shared.setup()
        let model = StatusViewModel()
        model.start()
        let updater = AppUpdater()
        _viewModel = StateObject(wrappedValue: model)
        appUpdater = updater
        settingsController = SettingsWindowController(viewModel: model, appUpdater: updater)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel, settingsController: settingsController)
        } label: {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                Image(systemName: viewModel.bannerText != nil ? "clock.badge.exclamationmark" : "clock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
