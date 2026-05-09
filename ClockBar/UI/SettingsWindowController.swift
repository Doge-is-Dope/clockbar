import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel: StatusViewModel

    init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
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

        let settingsView = SettingsView(
            viewModel: viewModel,
            onContentHeightChange: { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: AppStyle.Layout.settingsIdealWidth,
                height: 0
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hostingView
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

    private func applyContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0, let window else { return }

        var contentSize = window.contentRect(forFrameRect: window.frame).size
        if contentSize.height != contentHeight {
            contentSize.height = contentHeight
            window.setContentSize(contentSize)
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if (notification.object as? NSWindow) === window {
                window = nil
            }
        }
    }
}
