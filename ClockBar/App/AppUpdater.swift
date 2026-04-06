import Foundation
import Sparkle

// MARK: - AppUpdater

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastChecked: Date?

    private let updater: SPUUpdater
    private let delegate: UpdaterDelegate
    private let userDriver: SPUStandardUserDriver

    init(startingUpdater: Bool = true) {
        let isConfigured = Self.hasUpdateConfiguration
        let delegate = UpdaterDelegate()
        self.delegate = delegate
        canCheckForUpdates = isConfigured
        userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: delegate
        )

        if isConfigured {
            delegate.onCheckFinished = { [weak self] success in
                guard success else { return }
                self?.lastChecked = Date()
            }
            updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
            if startingUpdater {
                try? updater.start()
            }
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() {
        guard Self.hasUpdateConfiguration else { return }
        updater.checkForUpdates()
    }

    private static var hasUpdateConfiguration: Bool {
        let info = Bundle.main.infoDictionary
        let feedURL = info?["SUFeedURL"] as? String ?? ""
        let publicKey = info?["SUPublicEDKey"] as? String ?? ""
        return !feedURL.isEmpty
            && !publicKey.isEmpty
            && !publicKey.contains("$(")
    }
}

// MARK: - UpdaterDelegate

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @MainActor var onCheckFinished: ((_ success: Bool) -> Void)?

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        Task { @MainActor in
            onCheckFinished?(error == nil)
        }
    }
}
