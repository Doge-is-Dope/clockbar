import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
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
        // The window is created at height 0 and grows downward from its top edge
        // once SwiftUI reports the real height (see applyContentHeight). center()
        // on a height-0 window leaves the top edge at the screen's vertical
        // center, so it would open in the lower half — anchor the top edge in the
        // upper portion of the screen instead.
        if let visible = window.screen?.visibleFrame {
            window.setFrameTopLeftPoint(
                NSPoint(x: window.frame.origin.x, y: visible.maxY - visible.height * 0.1))
        }
        // With ARC, `self.window` owns the retain; AppKit's legacy close-time release
        // would otherwise over-release and leave a dangling pointer — crashing the
        // next showSettings().
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        installKeyMonitor()
    }

    private func applyContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0, let window else { return }

        let frame = window.frame
        var contentSize = window.contentRect(forFrameRect: frame).size
        let screenHeight = window.screen?.visibleFrame.height ?? AppStyle.Layout.settingsMaxHeight
        let resolvedHeight = min(
            contentHeight,
            AppStyle.Layout.settingsMaxHeight,
            screenHeight - AppStyle.Spacing.xxl * 2
        )
        guard contentSize.height != resolvedHeight else { return }

        // Keep the top edge fixed so the window grows downward like System
        // Settings. No AppKit animation here: SwiftUI animates the content
        // height and reports it every frame, so the window just follows —
        // animating each tick ourselves makes the two systems fight (jank).
        contentSize.height = resolvedHeight
        var newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        newFrame.origin.x = frame.origin.x
        newFrame.origin.y = frame.maxY - newFrame.height
        window.setFrame(newFrame, display: true)
    }

    /// The app has no Window menu, so ⌘W gets no default handling — close the
    /// Settings window ourselves while it's key.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow,
                event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers == "w"
            else { return event }
            window.performClose(nil)
            return nil
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if (notification.object as? NSWindow) === window {
                window = nil
                if let keyMonitor {
                    NSEvent.removeMonitor(keyMonitor)
                    self.keyMonitor = nil
                }
            }
        }
    }
}
