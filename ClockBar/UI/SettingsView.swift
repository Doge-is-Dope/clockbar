import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: StatusViewModel

    @State private var clockInDate = Date()
    @State private var clockOutDate = Date()

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
                autoPunchSection
                wakeSection
                appSection
                accountActionButton
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: AppStyle.Layout.settingsMinWidth, idealWidth: AppStyle.Layout.settingsIdealWidth)
        .onAppear {
            clockInDate = date(from: viewModel.config.schedule.clockin)
            clockOutDate = date(from: viewModel.config.schedule.clockout)
        }
        .onChange(of: viewModel.config.schedule.clockin) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockInDate, equalTo: parsed, toGranularity: .minute) {
                clockInDate = parsed
            }
        }
        .onChange(of: viewModel.config.schedule.clockout) { _, value in
            let parsed = date(from: value)
            if !calendar.isDate(clockOutDate, equalTo: parsed, toGranularity: .minute) {
                clockOutDate = parsed
            }
        }
    }

    // MARK: - Auto-punch

    private var autoPunchSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Auto-punch")

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xs) {
                cardContainer {
                    SettingsCardRow(
                        icon: "clock.arrow.2.circlepath",
                        label: "Auto-punch",
                    ) {
                        Toggle("", isOn: Binding(
                            get: { viewModel.config.autopunchEnabled },
                            set: { viewModel.setAutopunchEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "sunrise",
                        label: "Clock In",
                        isEnabled: isScheduleEditingEnabled
                    ) {
                        TimeFieldPicker(
                            date: $clockInDate,
                            isEnabled: isScheduleEditingEnabled
                        ) {
                            persistTime($0, for: .clockin)
                        }
                        .fixedSize()
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "sunset",
                        label: "Clock Out",
                        isEnabled: isScheduleEditingEnabled
                    ) {
                        TimeFieldPicker(
                            date: $clockOutDate,
                            isEnabled: isScheduleEditingEnabled
                        ) {
                            persistTime($0, for: .clockout)
                        }
                        .fixedSize()
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "dice",
                        label: "Random delay",
                        subtitle: randomDelaySubtitle,
                        isEnabled: isAutoPunchEditingEnabled
                    ) {
                        durationControl(
                            value: Binding(
                                get: { max(0, viewModel.config.randomDelayMax) },
                                set: { viewModel.setRandomDelayMax($0) }
                            ),
                            range: 0...3600,
                            step: 60,
                            zeroLabel: "Off",
                            isEnabled: isAutoPunchEditingEnabled
                        )
                    }

                    insetDivider

                    SettingsCardRow(
                        icon: "bell.badge",
                        label: "Missed punch prompt",
                        subtitle: "Ask before punching if the scheduled time has already passed.",
                        isEnabled: isAutoPunchEditingEnabled
                    ) {
                        Toggle("", isOn: Binding(
                            get: { viewModel.config.latePromptEnabled },
                            set: { viewModel.setLatePromptEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    if viewModel.config.latePromptEnabled {
                        insetDivider

                        SettingsCardRow(
                            icon: "clock.badge.questionmark",
                            label: "Prompt after",
                            subtitle: "How long past the scheduled time before asking.",
                            isEnabled: isAutoPunchEditingEnabled
                        ) {
                            durationControl(
                                value: Binding(
                                    get: { max(0, viewModel.config.lateThreshold) },
                                    set: { viewModel.setLateThreshold($0) }
                                ),
                                range: 0...3600,
                                step: 60,
                                zeroLabel: "Immediate",
                                isEnabled: isAutoPunchEditingEnabled && viewModel.config.latePromptEnabled
                            )
                        }
                    }
                }

                Text("Runs Monday to Friday and skips public holidays.")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, AppStyle.Spacing.xs)
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
                        get: { viewModel.config.wakeEnabled },
                        set: { _ in viewModel.toggleWake() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(viewModel.wakeSyncState.isApplying)
                    .opacity(viewModel.wakeSyncState.isApplying ? AppStyle.Opacity.disabled : 1)
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
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppStyle.Font.sectionTitle)
            .foregroundStyle(.primary)
            .padding(.leading, AppStyle.Spacing.xs)
    }

    private func cardContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.card, style: .continuous)
                .fill(Color(nsColor: .labelColor).opacity(AppStyle.Opacity.cardFill))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.card, style: .continuous))
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, AppStyle.Spacing.cardPadding
                     + AppStyle.Layout.iconBackgroundSize
                     + AppStyle.Spacing.xl)
    }

    private func durationControl(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        zeroLabel: String? = nil,
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: AppStyle.Spacing.sm) {
            Text(durationText(value.wrappedValue, zeroLabel: zeroLabel))
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
                    .foregroundStyle(viewModel.isAuthenticated ? .red : .primary)

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
                .fill(Color(nsColor: .labelColor).opacity(AppStyle.Opacity.cardFill))
        )
    }

    // MARK: - Helpers

    private var randomDelaySubtitle: String {
        let delay = max(0, viewModel.config.randomDelayMax)
        guard delay > 0 else {
            return "Punch exactly at the scheduled times."
        }
        let cin = viewModel.config.schedule.clockin
        let cout = viewModel.config.schedule.clockout
        let cinEnd = addMinutes(delay / 60, to: cin)
        let coutEnd = addMinutes(delay / 60, to: cout)
        return "In \(displayTime(cin)) – \(displayTime(cinEnd)), Out \(displayTime(cout)) – \(displayTime(coutEnd))."
    }

    private var wakeScheduleSubtitle: String {
        viewModel.wakeSyncState.message
            ?? "Wakes before scheduled auto-punch when plugged in."
    }

    private var isAutoPunchEditingEnabled: Bool {
        viewModel.config.autopunchEnabled
    }

    private var isScheduleEditingEnabled: Bool {
        viewModel.config.autopunchEnabled && !viewModel.wakeSyncState.isApplying
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

    private func persistTime(_ value: Date, for action: ClockAction) {
        let newTime = DateFormatter.shortTimeFormatter.string(from: value)
        switch action {
        case .clockin:
            guard newTime != viewModel.config.schedule.clockin else { return }
            viewModel.updateSchedule(clockIn: newTime)
        case .clockout:
            guard newTime != viewModel.config.schedule.clockout else { return }
            viewModel.updateSchedule(clockOut: newTime)
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func date(from value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        let hour = parts.indices.contains(0) ? parts[0] : 0
        let minute = parts.indices.contains(1) ? parts[1] : 0
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay)
            ?? startOfDay
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
        picker.isEnabled = isEnabled
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        nsView.isEnabled = isEnabled
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
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView(viewModel: StatusViewModel())
        .preferredColorScheme(.dark)
}
