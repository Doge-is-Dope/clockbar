import AppKit
import Foundation
import ServiceManagement
import UserNotifications
import WebKit

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var status: PunchStatus?
    @Published var config: ClockConfig
    @Published var isPunching = false
    @Published var isRefreshing = false
    @Published var scheduleExpanded = false
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var lastRefresh: Date?
    @Published var scheduleState: ScheduleState
    @Published var statusNote: String?

    private var timer: Timer?
    private var didEnsureLaunchAtLogin = false
    private var authWindowController: AuthWindowController?

    init() {
        let initialConfig = ConfigManager.load()
        self.config = initialConfig
        self.scheduleState = ClockService.currentScheduleState(config: initialConfig)
        syncSessionState()
    }

    var bannerText: String? {
        if let note = statusNote?.trimmedNonEmpty {
            return note
        }

        if let mismatch = scheduleState.mismatchSummary?.trimmedNonEmpty {
            return mismatch
        }

        return status?.error?.trimmedNonEmpty
    }

    var authStatusText: String {
        if isAuthenticating {
            return "Signing in…"
        }

        guard let session = AuthStore.loadSession(), session.hasUsableCookies else {
            return ""
        }

        guard let lastValidatedAt = session.lastValidatedAt else {
            return "Connected"
        }

        return "Last synced \(Self.authFormatter.string(from: lastValidatedAt))"
    }

    func start() {
        guard timer == nil else { return }
        ensureLaunchAtLogin()
        reloadScheduleState()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        syncSessionState()

        guard isAuthenticated else {
            status = .error("Sign in to 104 to enable status and punching.")
            lastRefresh = Date()
            return
        }

        isRefreshing = true
        Task.detached { [weak self] in
            let updatedStatus = await ClockService.getStatus()
            await self?.finishRefresh(with: updatedStatus)
        }
    }

    func punchNow() {
        guard isAuthenticated else {
            beginAuthentication()
            return
        }

        let beforeIn = status?.clockIn
        let beforeOut = status?.clockOut
        isPunching = true
        Task.detached { [weak self] in
            let updatedStatus = await ClockService.punch()
            await self?.finishPunch(with: updatedStatus, beforeIn: beforeIn, beforeOut: beforeOut)
        }
    }

    func toggleAutopunch() {
        setAutopunchEnabled(!config.autopunchEnabled)
    }

    func setAutopunchEnabled(_ isEnabled: Bool) {
        guard config.autopunchEnabled != isEnabled else { return }
        config.autopunchEnabled = isEnabled
        saveAndReload()
    }

    func updateSchedule(clockIn: String? = nil, clockOut: String? = nil) {
        var nextConfig = config

        if let clockIn {
            nextConfig.schedule.clockin = clockIn
        }

        if let clockOut {
            nextConfig.schedule.clockout = clockOut
        }

        guard nextConfig != config else { return }
        config = nextConfig
        saveAndReload()
    }

    func saveAndReload() {
        let pendingConfig = config
        Task.detached { [weak self] in
            do {
                let state = try ClockService.scheduleInstall(for: pendingConfig)
                await self?.finishScheduleInstall(with: state)
            } catch {
                await self?.finishScheduleInstallFailure(config: pendingConfig, error: error)
            }
        }
    }

    func signOut() {
        ClockService.clearSession()
        status = nil
        statusNote = nil
        syncSessionState()
    }

    func beginAuthentication() {
        if let controller = authWindowController {
            controller.start()
            return
        }

        isAuthenticating = true
        statusNote = nil

        let controller = AuthWindowController(
            onSession: { [weak self] session in
                guard let self else { return }
                do {
                    try ClockService.saveSession(session)
                    self.syncSessionState()
                    self.statusNote = nil
                    self.refresh()
                } catch {
                    self.statusNote = "Failed to save 104 session: \(error.localizedDescription)"
                }
            },
            onFinish: { [weak self] in
                self?.isAuthenticating = false
                self?.authWindowController = nil
                self?.syncSessionState()
            }
        )

        authWindowController = controller
        controller.start()
    }

    private func reloadScheduleState() {
        scheduleState = ClockService.currentScheduleState(config: config)
    }

    private func syncSessionState() {
        isAuthenticated = AuthStore.loadSession()?.hasUsableCookies == true
    }

    private func finishRefresh(with updatedStatus: PunchStatus) {
        syncSessionState()
        if !isPunching, status != updatedStatus {
            status = updatedStatus
        }
        lastRefresh = Date()
        isRefreshing = false
    }

    private func finishPunch(with updatedStatus: PunchStatus, beforeIn: String?, beforeOut: String?) {
        syncSessionState()
        status = updatedStatus
        isPunching = false
        lastRefresh = Date()

        if updatedStatus.error == nil {
            if updatedStatus.clockIn != beforeIn, let time = updatedStatus.clockIn {
                NotificationManager.shared.send("104 Clock", body: "Clocked in at \(time)")
            } else if updatedStatus.clockOut != beforeOut, let time = updatedStatus.clockOut {
                NotificationManager.shared.send("104 Clock", body: "Clocked out at \(time)")
            }
        } else {
            NotificationManager.shared.send(
                "104 Clock",
                body: "Punch failed",
                sound: UNNotificationSound(named: UNNotificationSoundName("Basso"))
            )
        }
    }

    private func finishScheduleInstall(with state: ScheduleState) {
        scheduleState = state
        statusNote = nil
    }

    private func finishScheduleInstallFailure(config: ClockConfig, error: Error) {
        scheduleState = ClockService.currentScheduleState(config: config)
        statusNote = "Saved schedule, but launchd reload failed: \(error.localizedDescription)"
    }

    private func setStatusNote(_ message: String?) {
        statusNote = message
    }

    private func ensureLaunchAtLogin() {
        guard !didEnsureLaunchAtLogin else { return }
        didEnsureLaunchAtLogin = true

        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Best effort. The app continues even if registration fails.
        }
    }

    deinit {
        timer?.invalidate()
    }

    private static let authFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class AuthWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
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
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
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
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if webView.url == nil, let url = URL(string: "https://pro.104.com.tw") {
            webView.load(URLRequest(url: url))
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !didFinish else { return }
        // Validation never auto-closed the window. Save whatever cookies we
        // captured so the normal refresh cycle can attempt to use them.
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

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
