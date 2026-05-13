import AppKit
import SwiftUI

@main
@MainActor
struct ClockBarApp: App {
    @NSApplicationDelegateAdaptor(ClockBarAppDelegate.self) private var appDelegate
    @StateObject private var app = AppContainer()

    init() {
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: app.viewModel, settingsController: app.settingsController)
        } label: {
            if !isRunningInSwiftUIPreviews {
                Image(systemName: app.viewModel.bannerText != nil ? "clock.badge.exclamationmark" : "clock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class ClockBarAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationManager.shared.handleURL(url)
        }
    }
}
