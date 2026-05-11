import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StatusViewModel
    var settingsController: SettingsWindowController?
    @Environment(\.colorScheme) private var colorScheme

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
        .onAppear { viewModel.refresh() }
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
        Button {
            if viewModel.sessionNeedsReauth {
                viewModel.beginAuthentication()
            } else {
                viewModel.punchNow()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.lg) {
                if viewModel.isPunching || viewModel.isAuthenticating {
                    Image(systemName: "progress.indicator")
                        .font(AppStyle.Font.bodyMedium)
                        .symbolEffect(.rotate, isActive: true)
                }

                Text(primaryActionTitle)
                    .font(AppStyle.Font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PunchButtonStyle())
        .disabled(viewModel.isPunching || viewModel.isAuthenticating)
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

    private var primaryActionTitle: String {
        if viewModel.isAuthenticating {
            return "Signing In..."
        }

        if viewModel.isPunching {
            return "Punching..."
        }

        if viewModel.sessionNeedsReauth {
            return "Sign In Again"
        }

        return punchButtonTitle
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
        if viewModel.isHolidayToday {
            let reason = viewModel.holidayName.trimmedNonEmpty ?? "holiday"
            return "Skipping today · \(reason)"
        }

        let hasClockIn = viewModel.status?.clockIn != nil
        let hasClockOut = viewModel.status?.clockOut != nil

        if let next = viewModel.nextPunch {
            if !hasClockIn {
                return "Clock in at \(displayTime(next.clockin)) · Out at \(displayTime(next.clockout))"
            }
            if !hasClockOut {
                return "Clock out at \(displayTime(next.clockout))"
            }
        }

        // Both done or no pre-computed times — show range
        let s = viewModel.config.schedule
        if s.clockin == s.clockinEnd && s.clockout == s.clockoutEnd {
            return "\(displayTime(s.clockin)) – \(displayTime(s.clockout))"
        }
        return
            "In \(displayTime(s.clockin)) – \(displayTime(s.clockinEnd)), Out \(displayTime(s.clockout)) – \(displayTime(s.clockoutEnd))"
    }

    private func displayTime(_ time: String) -> String {
        ScheduledTime(string: time)?.shortDisplayString ?? time
    }

    private func showSettings() {
        settingsController?.showSettings()
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

#Preview("Session Expired") {
    let vm = StatusViewModel()
    vm.isAuthenticated = true
    vm.status = .error(Clock104Error.unauthorized.localizedDescription)
    return ContentView(viewModel: vm)
}

#Preview("Signed Out") {
    ContentView(viewModel: StatusViewModel())
}
