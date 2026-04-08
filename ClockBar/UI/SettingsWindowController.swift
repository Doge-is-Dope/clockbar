import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let viewModel: StatusViewModel
    private let appUpdater: AppUpdater

    init(viewModel: StatusViewModel, appUpdater: AppUpdater) {
        self.viewModel = viewModel
        self.appUpdater = appUpdater
    }

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(viewModel: viewModel, appUpdater: appUpdater)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: AppStyle.Layout.settingsIdealWidth,
                height: 0
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: AppStyle.Layout.settingsMinWidth, height: 200)
        window.contentMaxSize = NSSize(width: AppStyle.Layout.settingsMaxWidth, height: .greatestFiniteMagnitude)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
