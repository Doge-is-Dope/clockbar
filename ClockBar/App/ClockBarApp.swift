import AppKit
import SwiftUI

@main
@MainActor
struct ClockBarApp: App {
    @StateObject private var app = AppContainer()

    init() {
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: app.viewModel, settingsController: app.settingsController)
        } label: {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                Image(systemName: app.viewModel.bannerText != nil ? "clock.badge.exclamationmark" : "clock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
