import SwiftUI
import Cocoa
import UserNotifications
import ServiceManagement

// MARK: - Config Model

struct ClockConfig: Codable {
    var schedule: Schedule
    var lateThresholdMin: Int
    var randomDelayMax: Int
    var server: ServerConfig
    var autopunchEnabled: Bool
    var wakeEnabled: Bool
    var wakeBeforeMin: Int

    struct Schedule: Codable {
        var clockin: String
        var clockout: String
    }

    struct ServerConfig: Codable {
        var port: Int
        var token: String
    }

    enum CodingKeys: String, CodingKey {
        case schedule
        case lateThresholdMin = "late_threshold_min"
        case randomDelayMax = "random_delay_max"
        case server
        case autopunchEnabled = "autopunch_enabled"
        case wakeEnabled = "wake_enabled"
        case wakeBeforeMin = "wake_before_min"
    }

    static let `default` = ClockConfig(
        schedule: .init(clockin: "09:00", clockout: "18:00"),
        lateThresholdMin: 20,
        randomDelayMax: 900,
        server: .init(port: 8104, token: ""),
        autopunchEnabled: true,
        wakeEnabled: false,
        wakeBeforeMin: 5
    )
}

// MARK: - Status Model

struct PunchStatus: Codable {
    let date: String?
    let clockIn: String?
    let clockOut: String?
    let clockInCode: Int?
    let error: String?
}

// MARK: - Config Manager

class ConfigManager {
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".104/config.json")

    static func load() -> ClockConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(ClockConfig.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: ClockConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configPath, options: .atomic)
    }
}

// MARK: - Notification Manager

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ title: String, body: String, sound: UNNotificationSound = .default) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}

// MARK: - Clock Service

class ClockService {
    static let pythonPath = "/opt/homebrew/bin/python3"

    static var scriptPath: String {
        if let resourcePath = Bundle.main.path(forResource: "clock104", ofType: "py") {
            return resourcePath
        }
        let dir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent("clock104.py")
    }

    static func run(_ args: [String]) -> (output: String, success: Bool) {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [scriptPath] + args
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, proc.terminationStatus == 0)
        } catch {
            return (error.localizedDescription, false)
        }
    }

    static func getStatus() -> PunchStatus? {
        let (output, success) = run(["status"])
        guard success, let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PunchStatus.self, from: data)
    }

    static func punch() -> String {
        let (output, _) = run(["punch"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func scheduleInstall() {
        _ = run(["schedule", "install"])
    }
}

// MARK: - View Model

@MainActor
class StatusViewModel: ObservableObject {
    @Published var status: PunchStatus?
    @Published var config: ClockConfig = ConfigManager.load()
    @Published var isPunching = false
    @Published var serverRunning = false
    @Published var lastRefresh: Date?

    private var timer: Timer?
    private var serverProcess: Process?

    var clockInTime: Date {
        get { timeStringToDate(config.schedule.clockin) }
        set { config.schedule.clockin = dateToTimeString(newValue); saveAndReload() }
    }

    var clockOutTime: Date {
        get { timeStringToDate(config.schedule.clockout) }
        set { config.schedule.clockout = dateToTimeString(newValue); saveAndReload() }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task.detached {
            let s = ClockService.getStatus()
            await MainActor.run {
                self.status = s
                self.lastRefresh = Date()
            }
        }
    }

    func punchNow() {
        let beforeIn = status?.clockIn
        let beforeOut = status?.clockOut
        isPunching = true
        Task.detached {
            _ = ClockService.punch()
            let s = ClockService.getStatus()
            await MainActor.run {
                self.status = s
                self.isPunching = false
                if let s = s, s.error == nil {
                    if s.clockIn != beforeIn, let t = s.clockIn {
                        NotificationManager.shared.send("104 Clock", body: "Clocked in at \(t)")
                    } else if s.clockOut != beforeOut, let t = s.clockOut {
                        NotificationManager.shared.send("104 Clock", body: "Clocked out at \(t)")
                    }
                } else {
                    NotificationManager.shared.send("104 Clock", body: "Punch failed",
                        sound: UNNotificationSound(named: UNNotificationSoundName("Basso")))
                }
            }
        }
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            objectWillChange.send()
        } catch {}
    }

    func toggleAutopunch() {
        config.autopunchEnabled.toggle()
        saveAndReload()
    }

    func toggleWake() {
        config.wakeEnabled.toggle()
        ConfigManager.save(config)
        if config.wakeEnabled {
            // Compute wake time: clockin minus wake_before_min
            let parts = config.schedule.clockin.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                var comps = DateComponents()
                comps.hour = parts[0]
                comps.minute = parts[1]
                if let clockin = Calendar.current.date(from: comps) {
                    let wake = clockin.addingTimeInterval(-Double(config.wakeBeforeMin) * 60)
                    let wakeComps = Calendar.current.dateComponents([.hour, .minute], from: wake)
                    let wakeTime = String(format: "%02d:%02d:00", wakeComps.hour ?? 0, wakeComps.minute ?? 0)
                    _ = runWithAdmin("pmset repeat wake MTWRF \(wakeTime)")
                }
            }
        } else {
            _ = runWithAdmin("pmset repeat cancel")
        }
        ClockService.scheduleInstall()
    }

    func toggleServer() {
        if serverRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    func saveAndReload() {
        ConfigManager.save(config)
        ClockService.scheduleInstall()
    }

    private func startServer() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ClockService.pythonPath)
        proc.arguments = [ClockService.scriptPath, "serve", "--port", String(config.server.port)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.serverRunning = false }
        }
        do {
            try proc.run()
            serverProcess = proc
            serverRunning = true
        } catch {
            serverRunning = false
        }
    }

    private func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        serverRunning = false
    }

    private func timeStringToDate(_ str: String) -> Date {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date() }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts[0]
        comps.minute = parts[1]
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func dateToTimeString(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private func runWithAdmin(_ command: String) -> Bool {
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
        serverProcess?.terminate()
    }
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject var vm: StatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("104 Clock").font(.headline)
                Spacer()
                Button(action: { vm.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Status
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Label(vm.status?.clockIn ?? "--:--", systemImage: "sunrise")
                    Spacer()
                    Label(vm.status?.clockOut ?? "--:--", systemImage: "sunset")
                }
                .font(.system(.title2, design: .monospaced))
            }

            Divider()

            // Schedule
            VStack(alignment: .leading, spacing: 6) {
                Text("Schedule").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text("Clock In")
                    Spacer()
                    DatePicker("", selection: $vm.clockInTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 80)
                }
                HStack {
                    Text("Clock Out")
                    Spacer()
                    DatePicker("", selection: $vm.clockOutTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 80)
                }
            }

            Divider()

            // Actions
            Button(action: { vm.punchNow() }) {
                HStack {
                    Spacer()
                    if vm.isPunching {
                        ProgressView().controlSize(.small)
                        Text("Punching...")
                    } else {
                        Image(systemName: "hand.tap")
                        Text("Punch Now")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isPunching)

            Toggle("Auto-punch", isOn: Binding(
                get: { vm.config.autopunchEnabled },
                set: { _ in vm.toggleAutopunch() }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Wake on Schedule", isOn: Binding(
                    get: { vm.config.wakeEnabled },
                    set: { _ in vm.toggleWake() }
                ))
                if vm.config.wakeEnabled {
                    Label("Requires AC power (plugged in)", systemImage: "powerplug")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { vm.launchAtLogin },
                set: { _ in vm.toggleLaunchAtLogin() }
            ))

            HStack {
                Toggle("HTTP Server", isOn: Binding(
                    get: { vm.serverRunning },
                    set: { _ in vm.toggleServer() }
                ))
                Spacer()
                if vm.serverRunning {
                    Text(":\(vm.config.server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
        .onAppear {
            NotificationManager.shared.setup()
            vm.start()
        }
    }
}

// MARK: - App

@main
struct ClockBarApp: App {
    @StateObject private var vm = StatusViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(vm: vm)
        } label: {
            Image(systemName: "clock")
        }
        .menuBarExtraStyle(.window)
    }
}
