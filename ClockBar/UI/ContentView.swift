import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StatusViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isAuthenticated {
                summarySection
                rowDivider
                actionsSection
                rowDivider
                automationSection
                rowDivider
            }
            if !viewModel.isAuthenticated {
                sessionActionRow
                rowDivider
            }
            settingsRow
            rowDivider
            quitRow
        }
        .padding(.top, AppStyle.Spacing.md)
        .frame(width: AppStyle.Layout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summarySection: some View {
        VStack(alignment: .trailing, spacing: AppStyle.Spacing.xl) {
            HStack(spacing: 0) {
                StatusMetric(
                    title: "Clock In",
                    icon: "arrow.down.to.line",
                    value: viewModel.status?.clockIn ?? "--:--"
                )

                StatusMetric(
                    title: "Clock Out",
                    icon: "arrow.up.to.line",
                    value: viewModel.status?.clockOut ?? "--:--"
                )
            }

            if let authStatusText {
                Text(authStatusText)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(AppStyle.Font.subheadlineMedium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.xxl)
        .padding(.vertical, AppStyle.Spacing.lg)
    }

    private var actionsSection: some View {
        Button(action: { viewModel.punchNow() }) {
            HStack(spacing: AppStyle.Spacing.lg) {
                if viewModel.isPunching {
                    Image(systemName: "progress.indicator")
                        .font(AppStyle.Font.bodyMedium)
                        .symbolEffect(.rotate, isActive: true)
                }

                Text(viewModel.isPunching ? "Punching..." : punchButtonTitle)
                    .font(AppStyle.Font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PunchButtonStyle())
        .disabled(viewModel.isPunching)
        .padding(.horizontal, AppStyle.Spacing.xl)
        .padding(.vertical, AppStyle.Spacing.sm)
    }

    private var sessionActionRow: some View {
        MenuPanelButton(
            action: { viewModel.beginAuthentication() },
            isEnabled: !viewModel.isAuthenticating
        ) { _ in
            HStack(spacing: AppStyle.Spacing.lg) {
                Label(
                    viewModel.isAuthenticating ? "Signing In..." : "Sign In",
                    systemImage: "person.crop.circle"
                )
                .font(AppStyle.Font.body)
                Spacer(minLength: AppStyle.Spacing.md)
            }
            .foregroundStyle(.secondary)
        }
        .padding(AppStyle.Spacing.md)
    }

    private var automationSection: some View {
        VStack(spacing: AppStyle.Spacing.xs) {
            MenuPanelToggleRow(
                title: "Auto-punch",
                icon: "clock.arrow.2.circlepath",
                isOn: Binding(
                    get: { viewModel.config.autopunchEnabled },
                    set: { newValue in
                        withAnimation(AppStyle.Animation.standard) {
                            viewModel.setAutopunchEnabled(newValue)
                        }
                    }
                )
            )

            if viewModel.config.autopunchEnabled {
                Text(punchWindowSummary)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, AppStyle.Spacing.md)
            }
        }
        .padding(AppStyle.Spacing.md)
    }

    private var quitRow: some View {
        MenuPanelButton(action: { NSApp.terminate(nil) }) { _ in
            HStack(spacing: AppStyle.Spacing.lg) {
                Label("Quit", systemImage: "power")
                    .font(AppStyle.Font.body)
                Spacer(minLength: AppStyle.Spacing.md)
            }
            .foregroundStyle(.secondary)
        }
        .padding(AppStyle.Spacing.md)
    }

    private var settingsRow: some View {
        MenuPanelButton(action: showSettings) { _ in
            HStack(spacing: AppStyle.Spacing.lg) {
                Label("Settings", systemImage: "gearshape")
                    .font(AppStyle.Font.body)
                Spacer(minLength: AppStyle.Spacing.md)
            }
            .foregroundStyle(.secondary)
        }
        .padding(AppStyle.Spacing.md)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(AppStyle.Palette.separator.opacity(AppStyle.Opacity.separator))
            .frame(height: AppStyle.Layout.dividerHeight)
            .padding(.horizontal, AppStyle.Spacing.md)
    }

    private var authStatusText: String? {
        viewModel.authStatusText.trimmedNonEmpty
    }

    private var errorText: String? {
        viewModel.bannerText?.trimmedNonEmpty
    }

    private var punchButtonTitle: String {
        if viewModel.status?.clockIn == nil {
            return "Clock In Now"
        }

        if viewModel.status?.clockOut == nil {
            return "Clock Out Now"
        }

        return "Punch Now"
    }

    private var punchWindowSummary: String {
        let cin = viewModel.config.schedule.clockin
        let cout = viewModel.config.schedule.clockout
        let delay = max(0, viewModel.config.randomDelayMax)

        if delay > 0 {
            let cinEnd = addMinutes(delay / 60, to: cin)
            let coutEnd = addMinutes(delay / 60, to: cout)
            return "In \(displayTime(cin)) – \(displayTime(cinEnd)), Out \(displayTime(cout)) – \(displayTime(coutEnd))"
        }

        return "\(displayTime(cin)) – \(displayTime(cout))"
    }

    private func displayTime(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let h = parts.indices.contains(0) ? parts[0] : 0
        let m = parts.indices.contains(1) ? parts[1] : 0
        let period = h >= 12 ? "PM" : "AM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", h12, m, period)
    }

    private func addMinutes(_ minutes: Int, to time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let h = parts.indices.contains(0) ? parts[0] : 0
        let m = parts.indices.contains(1) ? parts[1] : 0
        let total = h * 60 + m + minutes
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    private func showSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

#Preview("Signed In – Light") {
    let vm = StatusViewModel()
    vm.isAuthenticated = true
    vm.status = PunchStatus(date: "2026/04/05", clockIn: "09:03", clockOut: nil, clockInCode: nil, error: nil)
    return ContentView(viewModel: vm)
        .preferredColorScheme(.light)
}

#Preview("Signed In – Dark") {
    let vm = StatusViewModel()
    vm.isAuthenticated = true
    vm.status = PunchStatus(date: "2026/04/05", clockIn: "09:03", clockOut: "18:15", clockInCode: nil, error: nil)
    return ContentView(viewModel: vm)
        .preferredColorScheme(.dark)
}

#Preview("Signed Out") {
    ContentView(viewModel: StatusViewModel())
}
