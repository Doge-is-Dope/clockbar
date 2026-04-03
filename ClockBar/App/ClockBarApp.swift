import AppKit
import SwiftUI

@main
@MainActor
struct ClockBarApp: App {
    @StateObject private var viewModel: StatusViewModel

    init() {
        NotificationManager.shared.setup()
        let model = StatusViewModel()
        model.start()
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel)
        } label: {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                Image(systemName: viewModel.bannerText != nil ? "clock.badge.exclamationmark" : "clock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
