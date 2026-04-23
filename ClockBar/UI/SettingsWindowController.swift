import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel: StatusViewModel
    private let appUpdater: AppUpdater

    init(viewModel: StatusViewModel, appUpdater: AppUpdater) {
        self.viewModel = viewModel
        self.appUpdater = appUpdater
        super.init()
    }

    func showSettings() {
        // Defer to the next runloop turn so we don't re-enter AppKit while the
        // menu bar extra is still tearing down — caused the ghost icon bug (7d17fbb).
        DispatchQueue.main.async { [weak self] in
            self?.presentWindow()
        }
    }

    private func presentWindow() {
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
        // With ARC, `self.window` owns the retain; AppKit's legacy close-time release
        // would otherwise over-release and leave a dangling pointer — crashing the
        // next showSettings().
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if (notification.object as? NSWindow) === window {
                window = nil
            }
        }
    }
}
