import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: StatusViewModel
    @ObservedObject var appUpdater: AppUpdater

    @State private var clockInDate = Date()
    @State private var clockInEndDate = Date()
    @State private var clockOutDate = Date()
    @State private var clockOutEndDate = Date()
    @State private var maxContentHeight: CGFloat = 0
    @State private var shouldSnapInitialWindowHeight = true

    private let calendar = Calendar(identifier: .gregorian)
    private let contentPadding = AppStyle.Spacing.xxl + AppStyle.Spacing.xs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
                automationSection
                notificationsSection
                wakeSection
                appSection
                accountActionButton
            }
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SettingsContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .frame(
            minWidth: AppStyle.Layout.settingsMinWidth,
            idealWidth: AppStyle.Layout.settingsIdealWidth
        )
        .background(
            SettingsWindowHeightController(
                maxContentHeight: maxContentHeight,
                shouldSnapInitialHeight: shouldSnapInitialWindowHeight
            ) {
                shouldSnapInitialWindowHeight = false
            }
        )
        .onAppear {
            clockInDate = date(from: viewModel.config.schedule.clockin)
            clockInEndDate = date(from: viewModel.config.schedule.clockinEnd)
            clockOutDate = date(from: viewModel.config.schedule.clockout)
            clockOutEndDate = date(from: viewModel.config.schedule.clockoutEnd)
            shouldSnapInitialWindowHeight = true
        }
        .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
            maxContentHeight = height
        }
        .onDisappear {
            viewModel.commitWakeScheduleChangesOnClose()
        }
        .onChange(of: viewModel.config.schedule.clockin) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockInDate, equalTo: parsed, toGranularity: .minute) {
                clockInDate = parsed
            }
        }
        .onChange(of: viewModel.config.schedule.clockinEnd) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockInEndDate, equalTo: parsed, toGranularity: .minute) {
                clockInEndDate = parsed
            }
        }
        .onChange(of: viewModel.config.schedule.clockout) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockOutDate, equalTo: parsed, toGranularity: .minute) {
                clockOutDate = parsed
            }
        }
        .onChange(of: viewModel.config.schedule.clockoutEnd) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockOutEndDate, equalTo: parsed, toGranularity: .minute) {
                clockOutEndDate = parsed
            }
        }
    }

    // MARK: - Automation

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Automation")

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xs) {
                cardContainer {
                    SettingsCardRow(
                        icon: "clock.arrow.2.circlepath",
                        label: "Auto-punch"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { viewModel.config.autopunchEnabled },
                            set: { viewModel.setAutopunchEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .tint(AppStyle.Palette.accent)
                        .labelsHidden()
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "sunrise",
                        label: "Clock In"
                    ) {
                        timeRangePicker(
                            start: $clockInDate,
                            end: $clockInEndDate,
                            isEnabled: true
                        ) { startDate, endDate in
                            persistTimeRange(start: startDate, end: endDate, for: .clockin)
                        }
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "sunset",
                        label: "Clock Out"
                    ) {
                        timeRangePicker(
                            start: $clockOutDate,
                            end: $clockOutEndDate,
                            isEnabled: true
                        ) { startDate, endDate in
                            persistTimeRange(start: startDate, end: endDate, for: .clockout)
                        }
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "clock.badge.checkmark",
                        label: "Minimum hours",
                        subtitle: "Adjusts clock out if the gap is too short."
                    ) {
                        durationControl(
                            value: Binding(
                                get: { viewModel.config.minWorkHours },
                                set: { viewModel.setMinWorkHours($0) }
                            ),
                            range: 0...12,
                            step: 1,
                            formatter: { $0 == 0 ? "Off" : "\($0)h" }
                        )
                    }
                }

                if let warning = scheduleWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, AppStyle.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Notifications")

            cardContainer {
                SettingsCardRow(
                    icon: "bell.badge",
                    label: "Missed punch notification",
                    subtitle: "Notifies when no punch is recorded on time."
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.config.missedPunchNotificationEnabled },
                        set: { viewModel.setMissedPunchNotificationEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppStyle.Palette.accent)
                    .labelsHidden()
                }

                if viewModel.config.missedPunchNotificationEnabled {
                    insetDivider

                    SettingsCardRow(
                        icon: "clock.badge.questionmark",
                        label: "Notify after",
                        subtitle: "Delay after the scheduled time before notifying."
                    ) {
                        durationControl(
                            value: Binding(
                                get: { max(0, viewModel.config.missedPunchNotificationDelay) },
                                set: { viewModel.setMissedPunchNotificationDelay($0) }
                            ),
                            range: 0...3600,
                            step: 60,
                            zeroLabel: "Immediately"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Wake

    private var wakeSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Wake")

            cardContainer {
                SettingsCardRow(
                    icon: "powersleep",
                    label: "Wake for auto-punch",
                    subtitle: wakeScheduleSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.wakeEnabledDraft },
                        set: { viewModel.setWakeEnabledDraft($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppStyle.Palette.accent)
                    .labelsHidden()
                    .disabled(viewModel.wakeSyncState.isApplying)
                    .opacity(viewModel.wakeSyncState.isApplying ? AppStyle.Opacity.disabled : 1)
                }

                insetDivider

                SettingsCardRow(
                    icon: "alarm",
                    label: "Wake before",
                    subtitle: "Lead time before the scheduled punch."
                ) {
                    durationControl(
                        value: Binding(
                            get: { max(0, viewModel.wakeBeforeDraft) },
                            set: { viewModel.setWakeBeforeDraft($0) }
                        ),
                        range: 0...3600,
                        step: 60,
                        zeroLabel: "At punch time",
                        isEnabled: !viewModel.wakeSyncState.isApplying
                    )
                }
            }
        }
    }

    // MARK: - App

    private var appSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("App")

            cardContainer {
                SettingsCardRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Sync Status"
                ) {
                    durationControl(
                        value: Binding(
                            get: { max(60, viewModel.config.refreshInterval) },
                            set: { viewModel.setRefreshInterval($0) }
                        ),
                        range: 60...3600,
                        step: 60
                    )
                }

                insetDivider

                SettingsCardRow(
                    icon: "info.circle",
                    label: "ClockBar \(appUpdater.currentVersion)"
                ) {
                    VStack(alignment: .trailing, spacing: AppStyle.Spacing.xs) {
                        Button {
                            appUpdater.checkForUpdates()
                        } label: {
                            Text("Check for Updates")
                                .font(AppStyle.Font.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, AppStyle.Spacing.sm)
                                .padding(.vertical, AppStyle.Spacing.xs)
                                .background(AppStyle.Palette.accent, in: RoundedRectangle(cornerRadius: AppStyle.Radius.small))
                        }
                        .buttonStyle(.plain)

                        if let lastChecked = appUpdater.lastChecked {
                            Text("Last checked: \(lastChecked, format: .relative(presentation: .named))")
                                .font(AppStyle.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppStyle.Font.sectionTitle)
            .foregroundStyle(.primary)
    }

    private func cardContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.card, style: .continuous)
                .fill(AppStyle.Palette.label.opacity(AppStyle.Opacity.cardFill))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.card, style: .continuous))
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, AppStyle.Spacing.cardPadding
                     + AppStyle.Layout.iconBackgroundSize)
            .padding(.horizontal, AppStyle.Spacing.cardPadding)
    }

    private func durationControl(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        zeroLabel: String? = nil,
        formatter: ((Int) -> String)? = nil,
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: AppStyle.Spacing.sm) {
            Text(formatter?(value.wrappedValue) ?? durationText(value.wrappedValue, zeroLabel: zeroLabel))
                .font(AppStyle.Font.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: AppStyle.Layout.durationLabelWidth, alignment: .trailing)

            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
        .opacity(isEnabled ? 1 : AppStyle.Opacity.disabled)
        .disabled(!isEnabled)
    }

    private var accountActionButton: some View {
        Button {
            if viewModel.isAuthenticated {
                viewModel.signOut()
            } else {
                viewModel.beginAuthentication()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.xl) {
                Image(systemName: accountActionIcon)
                    .font(AppStyle.Font.icon)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: AppStyle.Layout.iconBackgroundSize,
                        height: AppStyle.Layout.iconBackgroundSize
                    )

                Text(accountActionTitle)
                    .font(AppStyle.Font.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: AppStyle.Spacing.md)
            }
            .frame(minHeight: AppStyle.Layout.settingsRowHeight)
            .padding(.horizontal, AppStyle.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAuthenticating)
        .opacity(viewModel.isAuthenticating ? AppStyle.Opacity.disabled : 1)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.card, style: .continuous)
                .fill(AppStyle.Palette.label.opacity(AppStyle.Opacity.cardFill))
        )
    }

    // MARK: - Helpers

    private var wakeScheduleSubtitle: String {
        viewModel.wakeStatusMessage
    }

    private var scheduleWarning: String? {
        let s = viewModel.config.schedule
        let inEnd = minutesSinceMidnight(s.clockinEnd)
        let outStart = minutesSinceMidnight(s.clockout)

        if outStart <= inEnd {
            return "Clock out must be later than clock in."
        }

        let minHours = viewModel.config.minWorkHours
        guard minHours > 0 else { return nil }

        let workHours = Double(outStart - inEnd) / 60
        if workHours < Double(minHours) {
            return String(format: "Only %.1f hours between clock in and out (minimum %d recommended).", workHours, minHours)
        }

        return nil
    }

    private var accountActionTitle: String {
        if viewModel.isAuthenticated {
            return "Sign Out"
        }

        return viewModel.isAuthenticating ? "Signing In..." : "Sign In"
    }

    private var accountActionIcon: String {
        viewModel.isAuthenticated ? "rectangle.portrait.and.arrow.right" : "person.crop.circle"
    }

    private func durationText(_ seconds: Int, zeroLabel: String? = nil) -> String {
        let normalized = max(0, seconds)
        if normalized == 0, let zeroLabel {
            return zeroLabel
        }
        if normalized < 60 || normalized % 60 != 0 {
            return "\(normalized)s"
        }
        return "\(normalized / 60)m"
    }

    private func timeRangePicker(
        start: Binding<Date>,
        end: Binding<Date>,
        isEnabled: Bool,
        onChange: @escaping (Date, Date) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.sm) {
            TimeFieldPicker(
                date: start,
                alignment: .center,
                isEnabled: isEnabled
            ) { newStart in
                var clampedEnd = end.wrappedValue
                if clampedEnd < newStart {
                    clampedEnd = newStart
                    end.wrappedValue = clampedEnd
                }
                onChange(newStart, clampedEnd)
            }

            Capsule()
                .fill(.tertiary)
                .frame(width: AppStyle.Layout.timeRangeSeparatorRuleWidth, height: 1)
                .frame(
                    width: AppStyle.Layout.timeRangeSeparatorWidth,
                    height: AppStyle.Layout.timeRangeSeparatorHeight,
                    alignment: .center
                )

            TimeFieldPicker(
                date: end,
                alignment: .center,
                isEnabled: isEnabled
            ) { newEnd in
                var clampedEnd = newEnd
                if clampedEnd < start.wrappedValue {
                    clampedEnd = start.wrappedValue
                    end.wrappedValue = clampedEnd
                }
                onChange(start.wrappedValue, clampedEnd)
            }
        }
    }

    private func persistTimeRange(start: Date, end: Date, for action: ClockAction) {
        let startTime = DateFormatter.shortTimeFormatter.string(from: start)
        let endTime = DateFormatter.shortTimeFormatter.string(from: end)
        let s = viewModel.config.schedule
        let startChanged: Bool
        let minGap = viewModel.config.minWorkHours * 60

        switch action {
        case .clockin:
            startChanged = startTime != s.clockin
            guard minGap > 0 else {
                viewModel.updateSchedule(
                    clockIn: startChanged ? startTime : nil,
                    clockInEnd: endTime
                )
                break
            }
            let inEndMinutes = minutesSinceMidnight(endTime)
            let outStartMinutes = minutesSinceMidnight(s.clockout)
            if outStartMinutes - inEndMinutes < minGap {
                let outWidth = minutesSinceMidnight(s.clockoutEnd) - minutesSinceMidnight(s.clockout)
                let newOutStart = inEndMinutes + minGap
                let newOut = formatMinutes(newOutStart)
                let newOutEnd = formatMinutes(newOutStart + max(outWidth, 0))
                clockOutDate = date(from: newOut)
                clockOutEndDate = date(from: newOutEnd)
                viewModel.updateSchedule(
                    clockIn: startChanged ? startTime : nil,
                    clockInEnd: endTime,
                    clockOut: newOut,
                    clockOutEnd: newOutEnd
                )
            } else {
                viewModel.updateSchedule(
                    clockIn: startChanged ? startTime : nil,
                    clockInEnd: endTime
                )
            }
        case .clockout:
            startChanged = startTime != s.clockout
            guard minGap > 0 else {
                viewModel.updateSchedule(
                    clockOut: startChanged ? startTime : nil,
                    clockOutEnd: endTime
                )
                break
            }
            let outStartMinutes = minutesSinceMidnight(startTime)
            let inEndMinutes = minutesSinceMidnight(s.clockinEnd)
            if outStartMinutes - inEndMinutes < minGap {
                let inWidth = minutesSinceMidnight(s.clockinEnd) - minutesSinceMidnight(s.clockin)
                let newInEnd = max(0, outStartMinutes - minGap)
                let newIn = formatMinutes(max(0, newInEnd - max(inWidth, 0)))
                let newInEndStr = formatMinutes(newInEnd)
                clockInDate = date(from: newIn)
                clockInEndDate = date(from: newInEndStr)
                viewModel.updateSchedule(
                    clockIn: newIn,
                    clockInEnd: newInEndStr,
                    clockOut: startChanged ? startTime : nil,
                    clockOutEnd: endTime
                )
            } else {
                viewModel.updateSchedule(
                    clockOut: startChanged ? startTime : nil,
                    clockOutEnd: endTime
                )
            }
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        ScheduledTime(totalMinutes: minutes).displayString
    }

    private func date(from value: String) -> Date {
        ScheduledTime(string: value)?.date(on: Date(), calendar: calendar)
            ?? calendar.startOfDay(for: Date())
    }
}

// MARK: - SettingsCardRow

private struct SettingsCardRow<Control: View>: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    var isEnabled = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xl) {
            HStack(spacing: AppStyle.Spacing.xl) {
                Image(systemName: icon)
                    .font(AppStyle.Font.icon)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: AppStyle.Layout.iconBackgroundSize,
                        height: AppStyle.Layout.iconBackgroundSize
                    )

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxs) {
                    Text(label)
                        .font(AppStyle.Font.body)
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(AppStyle.Font.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
            .opacity(isEnabled ? 1 : AppStyle.Opacity.disabled)

            Spacer(minLength: AppStyle.Spacing.md)

            control()
                .disabled(!isEnabled)
        }
        .frame(minHeight: AppStyle.Layout.settingsRowHeight)
        .padding(.horizontal, AppStyle.Spacing.cardPadding)
    }
}

// MARK: - TimeFieldPicker

private struct TimeFieldPicker: NSViewRepresentable {
    @Binding var date: Date
    var alignment: NSTextAlignment = .natural
    var isEnabled = true
    var onChange: (Date) -> Void

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.dateValue = date
        picker.isBordered = false
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.alignment = alignment
        picker.isEnabled = isEnabled
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.alignment = alignment
        guard nsView.dateValue != date else { return }
        nsView.dateValue = date
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: TimeFieldPicker
        init(_ parent: TimeFieldPicker) { self.parent = parent }

        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
            parent.onChange(sender.dateValue)
        }
    }
}

#Preview("Light") {
    SettingsView(viewModel: StatusViewModel(), appUpdater: AppUpdater(startingUpdater: false))
        .frame(width: AppStyle.Layout.settingsIdealWidth)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView(viewModel: StatusViewModel(), appUpdater: AppUpdater(startingUpdater: false))
        .frame(width: AppStyle.Layout.settingsIdealWidth)
        .preferredColorScheme(.dark)
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsWindowHeightController: NSViewRepresentable {
    let maxContentHeight: CGFloat
    let shouldSnapInitialHeight: Bool
    let onInitialHeightApplied: () -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard maxContentHeight > 0 else { return }

        let pendingMax = maxContentHeight
        let pendingSnap = shouldSnapInitialHeight
        let snapCallback = onInitialHeightApplied

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }

            if window.contentMaxSize.height != pendingMax {
                var maxSize = window.contentMaxSize
                maxSize.height = pendingMax
                window.contentMaxSize = maxSize
            }

            guard pendingSnap else { return }

            var contentSize = window.contentRect(forFrameRect: window.frame).size
            if contentSize.height != pendingMax {
                contentSize.height = pendingMax
                window.setContentSize(contentSize)
            }
            snapCallback()
        }
    }
}
