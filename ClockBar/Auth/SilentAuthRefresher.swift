import Foundation
import WebKit

@MainActor
final class SilentAuthRefresher: NSObject, WKNavigationDelegate {
    static func refresh() async -> Bool {
        let refresher = SilentAuthRefresher()
        return await refresher.run()
    }

    private let webView: WKWebView
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didAttemptValidation = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    private func run() async -> Bool {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self?.finish(false)
            }
            _ = webView.load(URLRequest(url: baseURL))
        }
    }

    private func finish(_ success: Bool) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        cont.resume(returning: success)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            await self?.attemptValidationIfNeeded()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish(false) }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        Task { @MainActor [weak self] in self?.finish(false) }
    }

    private func attemptValidationIfNeeded() async {
        guard !didAttemptValidation else { return }
        didAttemptValidation = true

        // Give JS-driven redirects a moment to settle before reading cookies.
        try? await Task.sleep(nanoseconds: 500_000_000)

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        do {
            let session = try await ClockService.createStoredSession(from: cookies)
            try ClockService.saveSession(session)
            finish(true)
        } catch {
            finish(false)
        }
    }
}
