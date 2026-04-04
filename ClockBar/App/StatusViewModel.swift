import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var status: PunchStatus?
    @Published var config: ClockConfig
    @Published var isPunching = false
    @Published var isRefreshing = false
    @Published var scheduleExpanded = false
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
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
        if scheduleState.mismatchSummary != nil {
            saveAndReload()
        }
        refresh()
        let refreshInterval = TimeInterval(max(60, config.refreshInterval))
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        syncSessionState()

        guard isAuthenticated else {
            status = .error("Sign in to 104 to enable status and punching.")
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

    func setAutopunchEnabled(_ isEnabled: Bool) {
        guard config.autopunchEnabled != isEnabled else { return }
        config.autopunchEnabled = isEnabled
        saveAndReload()
    }

    func toggleWake() {
        let enabling = !config.wakeEnabled
        config.wakeEnabled = enabling
        try? ConfigManager.save(config)
        objectWillChange.send()

        let clockinStr = config.schedule.clockin
        let wakeBefore = config.wakeBefore

        Task.detached { [weak self] in
            let success: Bool
            if enabling {
                guard let scheduled = ScheduledTime(string: clockinStr),
                      let clockin = Calendar.current.date(
                          bySettingHour: scheduled.hour, minute: scheduled.minute, second: 0, of: Date()
                      ) else {
                    await self?.revertWake(!enabling)
                    return
                }
                let wake = clockin.addingTimeInterval(-Double(wakeBefore))
                let wakeComps = Calendar.current.dateComponents([.hour, .minute], from: wake)
                let wakeTime = String(format: "%02d:%02d:00", wakeComps.hour ?? 0, wakeComps.minute ?? 0)
                success = Self.runWithAdmin("pmset repeat wake MTWRF \(wakeTime)")
            } else {
                success = Self.runWithAdmin("pmset repeat cancel")
            }

            if success {
                await self?.saveAndReload()
            } else {
                await self?.revertWake(!enabling)
            }
        }
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
        isRefreshing = false
    }

    private func finishPunch(with updatedStatus: PunchStatus, beforeIn: String?, beforeOut: String?) {
        syncSessionState()
        status = updatedStatus
        isPunching = false

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

    private func revertWake(_ value: Bool) {
        config.wakeEnabled = value
        try? ConfigManager.save(config)
        objectWillChange.send()
    }

    private nonisolated static func runWithAdmin(_ command: String) -> Bool {
        let script = "do shell script \"\(command)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
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
