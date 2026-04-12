import AppKit
import WebKit

final class AuthWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    private let webView: WKWebView
    private let onSession: @MainActor (StoredSession) -> Void
    private let onFinish: @MainActor () -> Void
    private var didFinish = false
    private var captureTask: Task<Void, Never>?
    private var lastCapturedCookies: [HTTPCookie] = []

    init(
        onSession: @escaping @MainActor (StoredSession) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.onSession = onSession
        self.onFinish = onFinish
        self.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        let window = NSWindow(
            contentRect: AppStyle.Layout.loginWindowSize,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In to 104"
        window.center()
        window.contentView = webView
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        // Undocumented KVC; acceptable here to keep the login sheet visually clean,
        // but it may break on a future macOS release.
        webView.setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func start() {
        didFinish = false
        lastCapturedCookies = []
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = webView.load(URLRequest(url: baseURL))
    }

    func windowWillClose(_ notification: Notification) {
        guard !didFinish else { return }
        let relevant = lastCapturedCookies.filter { $0.domain.contains("104") }
        if !relevant.isEmpty {
            let session = StoredSession(
                cookies: relevant.map(StoredCookie.init(cookie:)),
                lastValidatedAt: nil
            )
            complete(session: session)
        } else {
            complete(session: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        attemptSessionCapture()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        attemptSessionCapture()
    }

    private func attemptSessionCapture() {
        guard !didFinish else { return }
        captureTask?.cancel()
        captureTask = Task {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard !Task.isCancelled else { return }
            await MainActor.run { self.lastCapturedCookies = cookies }
            do {
                let session = try await ClockService.createStoredSession(from: cookies)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.complete(session: session)
                }
            } catch {
                // Not logged in yet, or validation failed — window stays open.
            }
        }
    }

    private func complete(session: StoredSession?) {
        guard !didFinish else { return }
        didFinish = true
        captureTask?.cancel()

        if let session {
            onSession(session)
        }
        onFinish()

        if window?.isVisible == true {
            window?.orderOut(nil)
            window?.close()
        }
    }
}

extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
