import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StatusViewModel
    var settingsController: SettingsWindowController?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isAuthenticated {
                summarySection
                rowDivider
            }

            primaryActionButton
            rowDivider

            if viewModel.isAuthenticated {
                automationSection
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
        VStack(alignment: .leading, spacing: AppStyle.Spacing.sm) {
            HStack(spacing: 0) {
                StatusMetric(
                    title: ClockAction.clockin.displayName,
                    icon: ClockAction.clockin.iconSystemName,
                    value: viewModel.status?.clockIn ?? "--:--"
                )

                StatusMetric(
                    title: ClockAction.clockout.displayName,
                    icon: ClockAction.clockout.iconSystemName,
                    value: viewModel.status?.clockOut ?? "--:--"
                )
            }
            .padding(.bottom, AppStyle.Spacing.sm)

            if viewModel.isHolidayToday {
                Label(holidaySummaryText, systemImage: "sun.max.fill")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.secondary)
            }

            activityRow

            if let reloginNoticeText {
                Text(reloginNoticeText)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(AppStyle.Font.subheadlineMedium)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.xxl)
        .padding(.vertical, AppStyle.Spacing.lg)
    }

    /// Worked-time and sync status share one line — worked on the left, the
    /// tappable sync status pushed to the right. Both tick via one `TimelineView`
    /// so the relative time stays current while the panel is open. `lastSyncedAt`
    /// is read once here (it hits disk) and threaded down.
    @ViewBuilder
    private var activityRow: some View {
        let syncedAt = viewModel.lastSyncedAt
        let showSync = viewModel.isRefreshing || viewModel.isAuthenticating || syncedAt != nil
        let showWorked = isStatusToday && viewModel.status?.clockIn != nil

        if showWorked || showSync {
            TimelineView(.everyMinute) { context in
                HStack(spacing: AppStyle.Spacing.sm) {
                    if showWorked, let workedText = workedSummary(now: context.date) {
                        Label(workedText, systemImage: "timer")
                            .font(AppStyle.Font.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showWorked, showSync {
                        Spacer(minLength: AppStyle.Spacing.sm)
                    }

                    if showSync {
                        syncRow(syncedAt: syncedAt, now: context.date)
                    }
                }
            }
        }
    }

    private func syncRow(syncedAt: Date?, now: Date) -> some View {
        Button {
            viewModel.refresh()
        } label: {
            HStack(spacing: AppStyle.Spacing.xs) {
                SyncIcon(isSpinning: viewModel.isRefreshing)
                syncLabel(syncedAt: syncedAt, now: now)
                    .contentTransition(.opacity)
            }
            .font(AppStyle.Font.caption)
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
            .animation(AppStyle.Animation.standard, value: viewModel.isRefreshing)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .help("Refresh status from 104")
    }

    @ViewBuilder
    private func syncLabel(syncedAt: Date?, now: Date) -> some View {
        if viewModel.isRefreshing {
            Text("Syncing…")
        } else if viewModel.isAuthenticating {
            Text("Signing in…")
        } else if let syncedAt {
            Text(StatusViewModel.syncedDescription(since: syncedAt, now: now))
        }
    }

    private var primaryActionButton: some View {
        Button {
            if isSignInAction {
                viewModel.beginAuthentication()
            } else {
                viewModel.punchNow()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.lg) {
                if viewModel.punchConfirmation != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppStyle.Font.bodyMedium)
                } else if viewModel.isPunching || viewModel.isAuthenticating {
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
        .disabled(viewModel.isPunching || viewModel.isAuthenticating || viewModel.punchConfirmation != nil)
        .animation(AppStyle.Animation.standard, value: viewModel.punchConfirmation)
        .padding(.horizontal, AppStyle.Spacing.xl)
        .padding(.vertical, AppStyle.Spacing.sm)
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
                Text("⌘Q")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(AppStyle.Palette.label)
        }
        .keyboardShortcut("q", modifiers: .command)
        .padding(AppStyle.Spacing.md)
    }

    private var settingsRow: some View {
        MenuPanelButton(action: showSettings) { _ in
            HStack(spacing: AppStyle.Spacing.lg) {
                Label("Settings", systemImage: "gearshape")
                    .font(AppStyle.Font.body)
                Spacer(minLength: AppStyle.Spacing.md)
                Text("⌘,")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(AppStyle.Palette.label)
        }
        .keyboardShortcut(",", modifiers: .command)
        .padding(AppStyle.Spacing.md)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(AppStyle.Palette.separator.opacity(AppStyle.Opacity.separator))
            .frame(height: AppStyle.Layout.dividerHeight)
            .padding(.horizontal, AppStyle.Spacing.md)
    }

    private var reloginNoticeText: String? {
        viewModel.reloginNoticeText?.trimmedNonEmpty
    }

    private var errorText: String? {
        viewModel.bannerText?.trimmedNonEmpty
    }

    private var isSignInAction: Bool {
        !viewModel.isAuthenticated || viewModel.sessionNeedsReauth
    }

    private var primaryActionTitle: String {
        if let confirmation = viewModel.punchConfirmation {
            return confirmation
        }

        if viewModel.isAuthenticating {
            return "Signing In..."
        }

        if viewModel.isPunching {
            return "Punching..."
        }

        if isSignInAction {
            return "Sign In"
        }

        return punchButtonTitle
    }

    private var punchButtonTitle: String {
        if viewModel.status?.clockIn == nil {
            return ClockAction.clockin.displayName
        }

        if viewModel.status?.clockOut == nil {
            return ClockAction.clockout.displayName
        }

        return "Punch Again"
    }

    private var isStatusToday: Bool {
        viewModel.status?.date == DateFormatter.statusDate.string(from: Date())
    }

    private var holidaySummaryText: String {
        if let name = viewModel.holidayName.trimmedNonEmpty {
            return "Holiday today — \(name)"
        }
        return "Holiday today"
    }

    /// "Worked 2h 10m so far" while clocked in, "Worked 9h 12m today" once
    /// both punches exist; nil when the times can't be parsed or span days.
    private func workedSummary(now: Date) -> String? {
        guard let clockIn = viewModel.status?.clockIn,
            let start = ScheduledTime(string: clockIn)
        else { return nil }

        let end: Date
        if let clockOut = viewModel.status?.clockOut {
            guard let out = ScheduledTime(string: clockOut) else { return nil }
            end = out.date(on: now)
        } else {
            end = now
        }

        let minutes = Int(end.timeIntervalSince(start.date(on: now)) / 60)
        guard minutes >= 0 else { return nil }

        let worked = formatDuration(minutes)
        return viewModel.status?.clockOut == nil ? "Worked \(worked) so far" : "Worked \(worked)"
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
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

/// A refresh glyph that spins at a constant rate while `isSpinning`, then stops
/// upright when idle. Rotation is derived from wall-clock time via
/// `TimelineView(.animation)` rather than a `repeatForever` animation, which
/// can't be reliably cancelled and stacks (each restart spins faster).
private struct SyncIcon: View {
    let isSpinning: Bool

    /// Seconds per full rotation.
    private let period: Double = 0.9

    var body: some View {
        if isSpinning {
            TimelineView(.animation) { context in
                let phase = (context.date.timeIntervalSinceReferenceDate / period)
                    .truncatingRemainder(dividingBy: 1)
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(phase * 360))
            }
        } else {
            Image(systemName: "arrow.clockwise")
        }
    }
}

#Preview("Signed In – Light") {
    let vm = StatusViewModel()
    vm.isAuthenticated = true
    vm.status = PunchStatus(
        date: DateFormatter.statusDate.string(from: Date()),
        clockIn: "09:03",
        clockOut: nil,
        clockInCode: nil,
        error: nil
    )
    return ContentView(viewModel: vm)
        .preferredColorScheme(.light)
}

#Preview("Signed In – Dark") {
    let vm = StatusViewModel()
    vm.isAuthenticated = true
    vm.status = PunchStatus(
        date: DateFormatter.statusDate.string(from: Date()),
        clockIn: "09:03",
        clockOut: "18:15",
        clockInCode: nil,
        error: nil
    )
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
