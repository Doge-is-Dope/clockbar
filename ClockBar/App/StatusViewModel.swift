import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StatusViewModel: ObservableObject {
    enum WakeSyncState: Equatable {
        case idle
        case applying
        case updated
        case failed(String)

        var isApplying: Bool {
            self == .applying
        }
    }

    @Published var status: PunchStatus?
    @Published var config: ClockConfig
    @Published var wakeEnabledDraft: Bool
    @Published var wakeBeforeDraft: Int
    @Published var isPunching = false
    @Published var isRefreshing = false
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var scheduleState: ScheduleState
    @Published var statusNote: String?
    @Published var wakeSyncState: WakeSyncState = .idle
    @Published var nextPunch: NextPunch?

    private var timer: Timer?
    private var didEnsureLaunchAtLogin = false
    private var authWindowController: AuthWindowController?
    private var wakeSyncStateResetTask: Task<Void, Never>?
    private var syncScheduleTask: Task<Void, Never>?
    private var appliedWakeSnapshot: WakeScheduleSnapshot
    private var sessionRecoveryTask: Task<Bool, Never>?

    private struct WakeScheduleSnapshot: Equatable {
        var wakeEnabled: Bool
        var wakeBefore: Int
        var clockIn: String

        init(config: ClockConfig, wakeEnabled: Bool? = nil, wakeBefore: Int? = nil) {
            self.wakeEnabled = wakeEnabled ?? config.wakeEnabled
            self.wakeBefore = wakeBefore ?? config.wakeBefore
            self.clockIn = config.schedule.clockin
        }
    }

    init() {
        let initialConfig = ConfigManager.load()
        self.config = initialConfig
        self.wakeEnabledDraft = initialConfig.wakeEnabled
        self.wakeBeforeDraft = initialConfig.wakeBefore
        self.appliedWakeSnapshot = WakeScheduleSnapshot(config: initialConfig)
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

    var hasPendingWakeChanges: Bool {
        currentWakeSnapshot != appliedWakeSnapshot
    }

    var wakeStatusMessage: String {
        switch wakeSyncState {
        case .applying:
            return "Saving..."
        case .failed(let message):
            return message
        case .updated where !hasPendingWakeChanges:
            return "Saved"
        default:
            if hasPendingWakeChanges {
                return "Saved when Settings closes."
            }
            if !wakeEnabledDraft {
                return "Disabled"
            }
            return "Wakes weekdays before clock-in (AC only). Clock-out won't wake a sleeping Mac."
        }
    }

    func start() {
        guard timer == nil else { return }
        ensureLaunchAtLogin()
        reloadScheduleState()
        if config.requiresScheduledJobs {
            if scheduleState.mismatchSummary != nil {
                syncScheduledJobs()
            }
        } else if LaunchAgentManager.hasInstalledPlists {
            syncScheduledJobs()
        }
        nextPunch = NextPunchStore.loadOrGenerate(config: config)
        refresh()
        installRefreshTimer()
    }

    func refresh() {
        guard !isRefreshing else { return }
        syncSessionState()

        guard isAuthenticated else {
            status = .error("Sign in to 104 to enable status and punching.")
            recoverSessionIfNeeded(trigger: "refresh_unauthenticated")
            return
        }

        isRefreshing = true
        Task.detached { [weak self] in
            let updatedStatus = await ClockService.getStatus()
            await self?.finishRefresh(with: updatedStatus)
        }
    }

    func punchNow() {
        guard !isPunching else { return }
        isPunching = true

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Silent-refresh first so the punch uses fresh cookies even when
            // the on-disk session is server-expired but structurally valid.
            let ok = await self.performSessionRecovery(trigger: "punch_now")
            guard ok else {
                self.isPunching = false
                Log.warn("manual", "skipped", ["reason": "auth_required"])
                self.beginAuthentication()
                return
            }

            let beforeIn = self.status?.clockIn
            let beforeOut = self.status?.clockOut
            let updatedStatus = await ClockService.punch()
            self.finishPunch(with: updatedStatus, beforeIn: beforeIn, beforeOut: beforeOut)
        }
    }

    func setAutopunchEnabled(_ isEnabled: Bool) {
        guard config.autopunchEnabled != isEnabled else { return }
        let shouldSyncJobs = config.requiresScheduledJobs != (isEnabled || config.missedPunchNotificationEnabled)
        let previousConfig = config
        config.autopunchEnabled = isEnabled
        let didSave = persistCurrentConfig(reloadScheduleState: !shouldSyncJobs)
        if didSave {
            if shouldSyncJobs { syncScheduledJobs() }
        } else {
            config = previousConfig
        }
    }

    func updateSchedule(
        clockIn: String? = nil,
        clockInEnd: String? = nil,
        clockOut: String? = nil,
        clockOutEnd: String? = nil
    ) {
        var nextConfig = config

        if let clockIn {
            nextConfig.schedule.clockin = clockIn
        }

        if let clockInEnd {
            nextConfig.schedule.clockinEnd = clockInEnd
        }

        if let clockOut {
            nextConfig.schedule.clockout = clockOut
        }

        if let clockOutEnd {
            nextConfig.schedule.clockoutEnd = clockOutEnd
        }

        guard nextConfig != config else { return }

        let startTimesChanged = nextConfig.schedule.clockin != config.schedule.clockin
            || nextConfig.schedule.clockout != config.schedule.clockout

        let previousConfig = config
        config = nextConfig
        if startTimesChanged {
            beginWakeEdit()
        }
        regenerateNextPunch()
        let didSave = persistCurrentConfig(reloadScheduleState: !startTimesChanged)

        if didSave {
            if startTimesChanged, config.requiresScheduledJobs {
                syncScheduledJobs()
            }
            if startTimesChanged,
               !appliedWakeSnapshot.wakeEnabled,
               !wakeEnabledDraft,
               wakeBeforeDraft == appliedWakeSnapshot.wakeBefore {
                appliedWakeSnapshot = currentWakeSnapshot
            }
        } else {
            config = previousConfig
            regenerateNextPunch()
        }
    }

    func setMinWorkHours(_ value: Int) {
        updateConfig(reloadScheduleState: true) {
            $0.minWorkHours = max(0, value)
        }
    }

    func setMissedPunchNotificationEnabled(_ isEnabled: Bool) {
        guard config.missedPunchNotificationEnabled != isEnabled else { return }
        let shouldSyncJobs = config.requiresScheduledJobs != (config.autopunchEnabled || isEnabled)
        let previousConfig = config
        config.missedPunchNotificationEnabled = isEnabled
        let didSave = persistCurrentConfig(reloadScheduleState: !shouldSyncJobs)
        if didSave {
            if shouldSyncJobs { syncScheduledJobs() }
        } else {
            config = previousConfig
        }
    }

    func setMissedPunchNotificationDelay(_ value: Int) {
        updateConfig(reloadScheduleState: true) {
            $0.missedPunchNotificationDelay = max(0, value)
        }
    }

    func setWakeEnabledDraft(_ value: Bool) {
        guard wakeEnabledDraft != value else { return }
        beginWakeEdit()
        wakeEnabledDraft = value
    }

    func setWakeBeforeDraft(_ value: Int) {
        let wakeBefore = max(0, value)
        guard wakeBeforeDraft != wakeBefore else { return }
        beginWakeEdit()
        wakeBeforeDraft = wakeBefore
    }

    func commitWakeScheduleChangesOnClose() {
        guard hasPendingWakeChanges, !wakeSyncState.isApplying else { return }

        wakeSyncStateResetTask?.cancel()
        let previousSnapshot = appliedWakeSnapshot
        let snapshot = currentWakeSnapshot

        if !previousSnapshot.wakeEnabled && !snapshot.wakeEnabled {
            commitWakeDraftWithoutPrivileges(snapshot: snapshot, previousSnapshot: previousSnapshot)
            return
        }

        wakeSyncState = .applying
        guard let command = Self.pmsetCommand(for: snapshot) else {
            wakeSyncState = .failed("Invalid wake schedule time.")
            return
        }

        Task { [weak self] in
            guard let self else { return }

            let success = await Task.detached(priority: .userInitiated) {
                Self.runWithAdmin(command)
            }.value

            guard !Task.isCancelled else { return }

            if success {
                self.appliedWakeSnapshot = snapshot
                self.config.wakeEnabled = self.wakeEnabledDraft
                self.config.wakeBefore = self.wakeBeforeDraft
                if self.persistCurrentConfig(reloadScheduleState: false) {
                    self.wakeSyncState = .updated
                    self.scheduleWakeSyncStateReset()
                } else {
                    self.wakeSyncState = .failed("Wake applied but failed to save config.")
                }
            } else {
                self.wakeEnabledDraft = previousSnapshot.wakeEnabled
                self.wakeBeforeDraft = previousSnapshot.wakeBefore
                self.wakeSyncState = .failed("Wake schedule permission was cancelled or failed.")
            }
        }
    }

    func setRefreshInterval(_ value: Int) {
        updateConfig(reloadScheduleState: true) {
            $0.refreshInterval = max(60, value)
        }
        restartRefreshTimerIfNeeded()
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

    private var currentWakeSnapshot: WakeScheduleSnapshot {
        WakeScheduleSnapshot(
            config: config,
            wakeEnabled: wakeEnabledDraft,
            wakeBefore: wakeBeforeDraft
        )
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
        refreshNextPunchIfNeeded()
        if updatedStatus.error == "Your 104 session expired. Sign in again." {
            recoverSessionIfNeeded(trigger: "status_expired")
        }
    }

    func recoverSessionIfNeeded(trigger: String = "background") {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.performSessionRecovery(trigger: trigger)
            if ok { self.refresh() }
        }
    }

    /// Single source of truth for re-validating the 104 session: silent-refresh
    /// cookies via the shared WebKit jar, log the attempt, sync the on-disk
    /// session into `isAuthenticated`, and return the resulting auth state.
    /// Concurrent callers coalesce onto one in-flight refresh.
    @discardableResult
    private func performSessionRecovery(trigger: String) async -> Bool {
        if let inflight = sessionRecoveryTask {
            return await inflight.value
        }
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            Log.info("auth.recovery", "started", ["trigger": trigger])
            let recovered = await SilentAuthRefresher.refresh()
            Log.info("auth.recovery", "completed", ["recovered": recovered ? "true" : "false"])
            self.syncSessionState()
            self.sessionRecoveryTask = nil
            return self.isAuthenticated
        }
        sessionRecoveryTask = task
        return await task.value
    }

    private func refreshNextPunchIfNeeded() {
        let today = DateFormatter.statusDateFormatter.string(from: Date())
        if nextPunch?.date != today {
            nextPunch = NextPunchStore.loadOrGenerate(config: config)
        }
    }

    private func regenerateNextPunch() {
        nextPunch = NextPunchStore.generate(config: config)
    }

    private func finishPunch(with updatedStatus: PunchStatus, beforeIn: String?, beforeOut: String?) {
        syncSessionState()
        status = updatedStatus
        isPunching = false

        if updatedStatus.error == nil {
            if updatedStatus.clockIn != beforeIn, let time = updatedStatus.clockIn {
                NotificationManager.shared.send(appName, body: "Clocked in at \(time)")
            } else if updatedStatus.clockOut != beforeOut, let time = updatedStatus.clockOut {
                NotificationManager.shared.send(appName, body: "Clocked out at \(time)")
            }
        } else {
            NotificationManager.shared.send(
                appName,
                body: "Punch failed",
                sound: UNNotificationSound(named: UNNotificationSoundName(notificationErrorSound))
            )
        }
    }

    private func finishScheduleSync(with state: ScheduleState) {
        scheduleState = state
        statusNote = nil
    }

    private func finishScheduleSyncFailure(config: ClockConfig, error: Error) {
        scheduleState = ClockService.currentScheduleState(config: config)
        statusNote = "Saved schedule, but launchd reload failed: \(error.localizedDescription)"
    }

    private func ensureLaunchAtLogin() {
        guard !didEnsureLaunchAtLogin else { return }
        didEnsureLaunchAtLogin = true

        // Only register the canonical /Applications copy so dev/test runs
        // don't create duplicate "Open at Login" entries per binary path.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }

        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Best effort. The app continues even if registration fails.
        }
    }

    private func updateConfig(
        reloadScheduleState: Bool,
        _ mutate: (inout ClockConfig) -> Void
    ) {
        var nextConfig = config
        mutate(&nextConfig)
        guard nextConfig != config else { return }
        let previousConfig = config
        config = nextConfig
        if !persistCurrentConfig(reloadScheduleState: reloadScheduleState) {
            config = previousConfig
        }
    }

    @discardableResult
    private func persistCurrentConfig(reloadScheduleState: Bool) -> Bool {
        do {
            try ConfigManager.save(config)
            if reloadScheduleState {
                self.reloadScheduleState()
            }
            return true
        } catch {
            statusNote = "Failed to save settings: \(error.localizedDescription)"
            return false
        }
    }

    private func syncScheduledJobs() {
        syncScheduleTask?.cancel()
        let pendingConfig = config
        syncScheduleTask = Task.detached { [weak self] in
            do {
                let state = try ClockService.syncSchedule(config: pendingConfig)
                guard !Task.isCancelled else { return }
                await self?.finishScheduleSync(with: state)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.finishScheduleSyncFailure(config: pendingConfig, error: error)
            }
        }
    }

    private func commitWakeDraftWithoutPrivileges(
        snapshot: WakeScheduleSnapshot,
        previousSnapshot: WakeScheduleSnapshot
    ) {
        config.wakeEnabled = wakeEnabledDraft
        config.wakeBefore = wakeBeforeDraft

        if persistCurrentConfig(reloadScheduleState: false) {
            appliedWakeSnapshot = snapshot
            wakeSyncState = .updated
            scheduleWakeSyncStateReset()
        } else {
            config.wakeEnabled = previousSnapshot.wakeEnabled
            config.wakeBefore = previousSnapshot.wakeBefore
            wakeEnabledDraft = previousSnapshot.wakeEnabled
            wakeBeforeDraft = previousSnapshot.wakeBefore
            wakeSyncState = .failed("Failed to save wake settings.")
        }
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

    private func scheduleWakeSyncStateReset() {
        wakeSyncStateResetTask?.cancel()
        wakeSyncStateResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.wakeSyncStateResetNanoseconds)
            guard !Task.isCancelled else { return }
            self?.clearWakeSyncStateIfUpdated()
        }
    }

    private func beginWakeEdit() {
        wakeSyncStateResetTask?.cancel()
        guard !wakeSyncState.isApplying else { return }
        wakeSyncState = .idle
    }

    private func clearWakeSyncStateIfUpdated() {
        guard wakeSyncState == .updated else { return }
        wakeSyncState = .idle
    }

    private nonisolated static func pmsetCommand(for snapshot: WakeScheduleSnapshot) -> String? {
        var commands = ["/usr/bin/pmset repeat cancel"]

        guard snapshot.wakeEnabled else {
            return commands.joined(separator: "; ")
        }

        guard let wakeTime = pmsetRepeatTime(for: snapshot) else {
            return nil
        }

        commands.append("/usr/bin/pmset repeat wakeorpoweron MTWRF \(wakeTime)")
        return commands.joined(separator: "; ")
    }

    private nonisolated static func pmsetRepeatTime(for snapshot: WakeScheduleSnapshot) -> String? {
        guard let clockIn = ScheduledTime(string: snapshot.clockIn) else { return nil }
        let clockInSeconds = clockIn.hour * 3600 + clockIn.minute * 60
        let dayInSeconds = 24 * 3600
        let wakeSeconds = ((clockInSeconds - max(0, snapshot.wakeBefore)) % dayInSeconds + dayInSeconds) % dayInSeconds
        return String(
            format: "%02d:%02d:%02d",
            wakeSeconds / 3600,
            (wakeSeconds % 3600) / 60,
            wakeSeconds % 60
        )
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
        syncScheduleTask?.cancel()
        wakeSyncStateResetTask?.cancel()
    }

    private static let wakeSyncStateResetNanoseconds: UInt64 = 2_000_000_000

    private static let authFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
