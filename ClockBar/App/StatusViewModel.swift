import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StatusViewModel: ObservableObject {
    enum WakeSyncState: Equatable {
        case idle
        case pending
        case applying
        case updated
        case failed(String)

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .pending, .applying:
                return "Updating..."
            case .updated:
                return "Updated"
            case .failed(let message):
                return message
            }
        }

        var isApplying: Bool {
            self == .applying
        }
    }

    @Published var status: PunchStatus?
    @Published var config: ClockConfig
    @Published var isPunching = false
    @Published var isRefreshing = false
    @Published var scheduleExpanded = false
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var scheduleState: ScheduleState
    @Published var statusNote: String?
    @Published var wakeSyncState: WakeSyncState = .idle

    private var timer: Timer?
    private var didEnsureLaunchAtLogin = false
    private var authWindowController: AuthWindowController?
    private var wakeApplyTask: Task<Void, Never>?
    private var wakeSyncStateResetTask: Task<Void, Never>?
    private var wakeRollbackSnapshot: WakeScheduleSnapshot?

    private struct WakeScheduleSnapshot: Equatable {
        var wakeEnabled: Bool
        var wakeBefore: Int
        var clockIn: String
        var clockOut: String

        init(config: ClockConfig) {
            self.wakeEnabled = config.wakeEnabled
            self.wakeBefore = config.wakeBefore
            self.clockIn = config.schedule.clockin
            self.clockOut = config.schedule.clockout
        }
    }

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
        installRefreshTimer()
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
        guard !wakeSyncState.isApplying else { return }

        let previousConfig = config
        let enabling = !config.wakeEnabled
        config.wakeEnabled = enabling
        try? ConfigManager.save(config)
        requestWakeScheduleApply(revertingTo: previousConfig, debounce: false)
    }

    func updateSchedule(clockIn: String? = nil, clockOut: String? = nil) {
        var nextConfig = config
        let previousConfig = config

        if let clockIn {
            nextConfig.schedule.clockin = clockIn
        }

        if let clockOut {
            nextConfig.schedule.clockout = clockOut
        }

        guard nextConfig != config else { return }
        config = nextConfig

        guard config.wakeEnabled, clockIn != nil || clockOut != nil else {
            saveAndReload()
            return
        }

        try? ConfigManager.save(config)
        requestWakeScheduleApply(revertingTo: previousConfig, debounce: true)
    }

    func setLatePromptEnabled(_ isEnabled: Bool) {
        updateConfig {
            $0.latePromptEnabled = isEnabled
        }
    }

    func setLateThreshold(_ value: Int) {
        updateConfig {
            $0.lateThreshold = max(0, value)
        }
    }

    func setRandomDelayMax(_ value: Int) {
        updateConfig {
            $0.randomDelayMax = max(0, value)
        }
    }

    func setWakeBefore(_ value: Int) {
        guard !wakeSyncState.isApplying else { return }

        let wakeBefore = max(0, value)
        guard config.wakeBefore != wakeBefore else { return }

        let previousConfig = config
        config.wakeBefore = wakeBefore

        guard config.wakeEnabled else {
            saveAndReload()
            return
        }

        try? ConfigManager.save(config)
        requestWakeScheduleApply(revertingTo: previousConfig, debounce: true)
    }

    func setRefreshInterval(_ value: Int) {
        updateConfig {
            $0.refreshInterval = max(60, value)
        }
        restartRefreshTimerIfNeeded()
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

    private func updateConfig(_ mutate: (inout ClockConfig) -> Void) {
        var nextConfig = config
        mutate(&nextConfig)
        guard nextConfig != config else { return }
        config = nextConfig
        saveAndReload()
    }

    private func installRefreshTimer() {
        timer?.invalidate()
        let refreshInterval = TimeInterval(max(60, config.refreshInterval))
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func restartRefreshTimerIfNeeded() {
        guard let timer else { return }
        let currentInterval = TimeInterval(max(60, config.refreshInterval))
        guard timer.timeInterval != currentInterval else { return }
        installRefreshTimer()
    }

    private func requestWakeScheduleApply(revertingTo previousConfig: ClockConfig, debounce: Bool) {
        if wakeRollbackSnapshot == nil {
            wakeRollbackSnapshot = WakeScheduleSnapshot(config: previousConfig)
        }

        wakeSyncStateResetTask?.cancel()
        wakeApplyTask?.cancel()
        wakeSyncState = debounce ? .pending : .applying

        let targetSnapshot = WakeScheduleSnapshot(config: config)
        wakeApplyTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: Self.wakeApplyDebounceNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await self?.performWakeScheduleApply(using: targetSnapshot)
        }
    }

    private func performWakeScheduleApply(using snapshot: WakeScheduleSnapshot) async {
        wakeSyncState = .applying

        let previousSnapshot = wakeRollbackSnapshot ?? snapshot
        guard let command = Self.pmsetCommand(replacing: previousSnapshot, with: snapshot) else {
            revertWakeSettings(message: "Invalid wake schedule time.")
            return
        }

        let success = await Task.detached(priority: .userInitiated) {
            Self.runWithAdmin(command)
        }.value

        guard !Task.isCancelled else { return }

        if success {
            wakeRollbackSnapshot = nil
            wakeSyncState = .updated
            scheduleWakeSyncStateReset()
            saveAndReload()
        } else {
            revertWakeSettings(message: "Wake schedule permission was cancelled or failed.")
        }
    }

    private func revertWakeSettings(message: String) {
        wakeSyncStateResetTask?.cancel()

        if let wakeRollbackSnapshot {
            config.wakeEnabled = wakeRollbackSnapshot.wakeEnabled
            config.wakeBefore = wakeRollbackSnapshot.wakeBefore
            config.schedule.clockin = wakeRollbackSnapshot.clockIn
            config.schedule.clockout = wakeRollbackSnapshot.clockOut
            self.wakeRollbackSnapshot = nil
            try? ConfigManager.save(config)
            saveAndReload()
        }

        wakeSyncState = .failed(message)
    }

    private func scheduleWakeSyncStateReset() {
        wakeSyncStateResetTask?.cancel()
        wakeSyncStateResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.wakeSyncStateResetNanoseconds)
            guard !Task.isCancelled else { return }
            self?.clearWakeSyncStateIfUpdated()
        }
    }

    private func clearWakeSyncStateIfUpdated() {
        guard wakeSyncState == .updated else { return }
        wakeSyncState = .idle
    }

    private nonisolated static func pmsetCommand(
        replacing previousSnapshot: WakeScheduleSnapshot,
        with snapshot: WakeScheduleSnapshot
    ) -> String? {
        var commands = ["/usr/bin/pmset repeat cancel"]

        if previousSnapshot.wakeEnabled {
            guard let previousWakeCommands = wakeScheduleCommands(
                for: previousSnapshot,
                actionPrefix: "/usr/bin/pmset schedule cancel wake"
            ) else {
                return nil
            }

            commands.append(contentsOf: previousWakeCommands.map { "\($0) >/dev/null 2>&1 || true" })
        }

        guard snapshot.wakeEnabled else {
            return commands.joined(separator: "; ")
        }

        guard let wakeCommands = wakeScheduleCommands(
            for: snapshot,
            actionPrefix: "/usr/bin/pmset schedule wake"
        ) else {
            return nil
        }

        commands.append(contentsOf: wakeCommands)
        return commands.joined(separator: "; ")
    }

    private nonisolated static func wakeScheduleCommands(
        for snapshot: WakeScheduleSnapshot,
        actionPrefix: String
    ) -> [String]? {
        guard let clockIn = ScheduledTime(string: snapshot.clockIn),
              let clockOut = ScheduledTime(string: snapshot.clockOut) else {
            return nil
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy HH:mm:ss"

        return (0..<wakeScheduleDayCount).flatMap { dayOffset -> [String] in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  !calendar.isDateInWeekend(date) else {
                return []
            }

            return [
                wakeScheduleCommand(
                    actionPrefix: actionPrefix,
                    date: date,
                    scheduledTime: clockIn,
                    owner: clockInWakeOwner,
                    now: now,
                    calendar: calendar,
                    formatter: formatter
                ),
                wakeScheduleCommand(
                    actionPrefix: actionPrefix,
                    date: date,
                    scheduledTime: clockOut,
                    owner: clockOutWakeOwner,
                    now: now,
                    calendar: calendar,
                    formatter: formatter
                ),
            ].compactMap { $0 }
        }
    }

    private nonisolated static func wakeScheduleCommand(
        actionPrefix: String,
        date: Date,
        scheduledTime: ScheduledTime,
        owner: String,
        now: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> String? {
        guard let punchDate = calendar.date(
            bySettingHour: scheduledTime.hour,
            minute: scheduledTime.minute,
            second: 0,
            of: date
        ) else {
            return nil
        }

        let wakeDate = punchDate.addingTimeInterval(-wakeLeadTimeInterval)
        guard wakeDate > now else { return nil }

        return "\(actionPrefix) '\(formatter.string(from: wakeDate))' \(owner)"
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
        wakeApplyTask?.cancel()
        wakeSyncStateResetTask?.cancel()
    }

    private static let wakeApplyDebounceNanoseconds: UInt64 = 800_000_000
    private static let wakeSyncStateResetNanoseconds: UInt64 = 2_000_000_000
    private static let wakeLeadTimeInterval: TimeInterval = 5 * 60
    private static let wakeScheduleDayCount = 366
    private static let clockInWakeOwner = "ClockBarClockInWake"
    private static let clockOutWakeOwner = "ClockBarClockOutWake"

    private static let authFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
