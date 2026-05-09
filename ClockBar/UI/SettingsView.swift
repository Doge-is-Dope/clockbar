import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: StatusViewModel
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    @State private var clockInDate = Date()
    @State private var clockInEndDate = Date()
    @State private var clockOutDate = Date()
    @State private var clockOutEndDate = Date()
    @State private var lastReportedContentHeight: CGFloat = 0

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        Form {
            automationSection
            notificationsSection
            wakeSection
            appSection
            accountSection
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            minWidth: AppStyle.Layout.settingsMinWidth,
            idealWidth: AppStyle.Layout.settingsIdealWidth
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onAppear {
            clockInDate = date(from: viewModel.config.schedule.clockin)
            clockInEndDate = date(from: viewModel.config.schedule.clockinEnd)
            clockOutDate = date(from: viewModel.config.schedule.clockout)
            clockOutEndDate = date(from: viewModel.config.schedule.clockoutEnd)
        }
        .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
            guard height > 0, height != lastReportedContentHeight else { return }
            lastReportedContentHeight = height
            onContentHeightChange?(height)
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
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.config.autopunchEnabled },
                set: { viewModel.setAutopunchEnabled($0) }
            )) {
                Label("Auto-punch", systemImage: "clock.arrow.2.circlepath")
            }
            .tint(AppStyle.Palette.accent)

            LabeledContent {
                timeRangePicker(
                    start: $clockInDate,
                    end: $clockInEndDate,
                    isEnabled: true
                ) { startDate, endDate in
                    persistTimeRange(start: startDate, end: endDate, for: .clockin)
                }
            } label: {
                Label("Clock In", systemImage: "sunrise")
            }

            LabeledContent {
                timeRangePicker(
                    start: $clockOutDate,
                    end: $clockOutEndDate,
                    isEnabled: true
                ) { startDate, endDate in
                    persistTimeRange(start: startDate, end: endDate, for: .clockout)
                }
            } label: {
                Label("Clock Out", systemImage: "sunset")
            }

            durationPicker(
                value: Binding(
                    get: { viewModel.config.minWorkHours },
                    set: { viewModel.setMinWorkHours($0) }
                ),
                options: DurationOption.minWorkHours,
                formatter: { $0 == 0 ? "Off" : "\($0)h" }
            ) {
                rowLabel(
                    title: "Minimum hours",
                    subtitle: "Pushes clock-out later if the workday falls short.",
                    icon: "clock.badge.checkmark"
                )
            }
        } header: {
            Text("Automation")
        } footer: {
            if let warning = scheduleWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: Binding(
                get: { viewModel.config.missedPunchNotificationEnabled },
                set: { viewModel.setMissedPunchNotificationEnabled($0) }
            )) {
                rowLabel(
                    title: "Missed punch notification",
                    subtitle: "Notifies when no punch is recorded on time.",
                    icon: "bell.badge"
                )
            }
            .tint(AppStyle.Palette.accent)

            if viewModel.config.missedPunchNotificationEnabled {
                durationPicker(
                    value: Binding(
                        get: { max(0, viewModel.config.missedPunchNotificationDelay) },
                        set: { viewModel.setMissedPunchNotificationDelay($0) }
                    ),
                    options: DurationOption.notifyAfter,
                    zeroLabel: "Immediately"
                ) {
                    rowLabel(
                        title: "Notify after",
                        subtitle: "Wait this long after the scheduled time.",
                        icon: "clock.badge.questionmark"
                    )
                }
            }
        }
    }

    // MARK: - Wake

    private var wakeSection: some View {
        Section("Sleep & Wake") {
            Toggle(isOn: Binding(
                get: { viewModel.wakeEnabledDraft },
                set: { viewModel.setWakeEnabledDraft($0) }
            )) {
                rowLabel(
                    title: "Wake for auto-punch",
                    subtitle: viewModel.wakeStatusMessage,
                    icon: "powersleep"
                )
            }
            .tint(AppStyle.Palette.accent)
            .disabled(viewModel.wakeSyncState.isApplying)

            durationPicker(
                value: Binding(
                    get: { max(0, viewModel.wakeBeforeDraft) },
                    set: { viewModel.setWakeBeforeDraft($0) }
                ),
                options: DurationOption.wakeBefore,
                zeroLabel: "At punch time"
            ) {
                rowLabel(
                    title: "Wake before",
                    subtitle: "How early to wake the Mac.",
                    icon: "alarm"
                )
            }
            .disabled(viewModel.wakeSyncState.isApplying)
        }
    }

    // MARK: - App

    private var appSection: some View {
        Section("General") {
            durationPicker(
                value: Binding(
                    get: { max(60, viewModel.config.refreshInterval) },
                    set: { viewModel.setRefreshInterval($0) }
                ),
                options: DurationOption.syncStatus
            ) {
                Label("Refresh interval", systemImage: "arrow.triangle.2.circlepath")
            }

            Label("ClockBar \(appVersion)", systemImage: "info.circle")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            Button {
                if viewModel.isAuthenticated {
                    viewModel.signOut()
                } else {
                    viewModel.beginAuthentication()
                }
            } label: {
                Label(accountActionTitle, systemImage: accountActionIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAuthenticating)
        }
    }

    // MARK: - Pickers

    private func durationPicker<Label: View>(
        value: Binding<Int>,
        options: [DurationOption],
        zeroLabel: String? = nil,
        formatter: ((Int) -> String)? = nil,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let current = value.wrappedValue
        let resolvedFormatter: (Int) -> String = formatter ?? { [zeroLabel] in
            durationText($0, zeroLabel: zeroLabel)
        }
        let merged = mergedOptions(
            options,
            current: current,
            formatter: resolvedFormatter
        )

        return Picker(selection: value) {
            ForEach(merged) { opt in
                Text(opt.label).tag(opt.value)
            }
        } label: {
            label()
        }
        .pickerStyle(.menu)
    }

    private func mergedOptions(
        _ base: [DurationOption],
        current: Int,
        formatter: (Int) -> String
    ) -> [DurationOption] {
        if base.contains(where: { $0.value == current }) {
            return base
        }
        let synthetic = DurationOption(value: current, label: formatter(current))
        return (base + [synthetic]).sorted { $0.value < $1.value }
    }

    // MARK: - Row labels

    @ViewBuilder
    private func rowLabel(title: String, subtitle: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxs) {
                Text(title)
                Text(subtitle)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    // MARK: - Helpers

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
    SettingsView(viewModel: StatusViewModel())
        .frame(width: AppStyle.Layout.settingsIdealWidth)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView(viewModel: StatusViewModel())
        .frame(width: AppStyle.Layout.settingsIdealWidth)
        .preferredColorScheme(.dark)
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - DurationOption

struct DurationOption: Identifiable {
    let value: Int
    let label: String
    var id: Int { value }

    static let minWorkHours: [DurationOption] = [
        .init(value: 0, label: "Off"),
        .init(value: 6, label: "6h"),
        .init(value: 7, label: "7h"),
        .init(value: 8, label: "8h"),
        .init(value: 9, label: "9h"),
        .init(value: 10, label: "10h"),
    ]

    static let notifyAfter: [DurationOption] = [
        .init(value: 0, label: "Immediately"),
        .init(value: 60, label: "1m"),
        .init(value: 300, label: "5m"),
        .init(value: 600, label: "10m"),
        .init(value: 900, label: "15m"),
        .init(value: 1800, label: "30m"),
        .init(value: 3600, label: "1h"),
    ]

    static let wakeBefore: [DurationOption] = [
        .init(value: 0, label: "At punch time"),
        .init(value: 60, label: "1m"),
        .init(value: 120, label: "2m"),
        .init(value: 300, label: "5m"),
        .init(value: 600, label: "10m"),
        .init(value: 900, label: "15m"),
        .init(value: 1800, label: "30m"),
    ]

    static let syncStatus: [DurationOption] = [
        .init(value: 60, label: "1m"),
        .init(value: 300, label: "5m"),
        .init(value: 600, label: "10m"),
        .init(value: 900, label: "15m"),
        .init(value: 1800, label: "30m"),
        .init(value: 3600, label: "1h"),
    ]
}
