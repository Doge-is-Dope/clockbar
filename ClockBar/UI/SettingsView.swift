import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: StatusViewModel

    @State private var clockInDate = Date()
    @State private var clockOutDate = Date()

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
                scheduleSection
                automationSection
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

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Schedule")

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xs) {
                cardContainer {
                    SettingsCardRow(
                        icon: "clock.arrow.2.circlepath",
                        label: "Auto-punch",
                        subtitle: "Clock in and out automatically at the times below."
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
                }

                Text("Runs on weekdays and skips public holidays.")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, AppStyle.Spacing.xs)
            }
        }
    }

    // MARK: - Automation

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxl) {
            sectionHeader("Automation")

            cardContainer {
                SettingsCardRow(icon: "bell.badge", label: "Late reminder", subtitle: "Nudge after this long past clock-in time.") {
                    durationControl(
                        value: Binding(
                            get: { max(0, viewModel.config.lateThreshold) },
                            set: { viewModel.setLateThreshold($0) }
                        ),
                        range: 0...3600,
                        step: 60
                    )
                }

                insetDivider

                SettingsCardRow(
                    icon: "dice",
                    label: "Random delay",
                    subtitle: delayRangeText
                ) {
                    durationControl(
                        value: Binding(
                            get: { max(0, viewModel.config.randomDelayMax) },
                            set: { viewModel.setRandomDelayMax($0) }
                        ),
                        range: 0...3600,
                        step: 60
                    )
                }

                insetDivider

                SettingsCardRow(
                    icon: "powersleep",
                    label: "Wake on Schedule",
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

                insetDivider

                SettingsCardRow(icon: "alarm", label: "Wake lead time", subtitle: "How early to wake your Mac before clock-in.") {
                    durationControl(
                        value: Binding(
                            get: { max(0, viewModel.config.wakeBefore) },
                            set: { viewModel.setWakeBefore($0) }
                        ),
                        range: 0...3600,
                        step: 60,
                        isEnabled: viewModel.config.wakeEnabled && !viewModel.wakeSyncState.isApplying
                    )
                }

                insetDivider

                SettingsCardRow(icon: "arrow.clockwise", label: "Auto-refresh", subtitle: "How often to check your punch status.") {
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
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: AppStyle.Spacing.sm) {
            Text(durationText(value.wrappedValue))
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

    // MARK: - Helpers

    private var delayRangeText: String? {
        let delay = max(0, viewModel.config.randomDelayMax)
        guard delay > 0 else { return nil }
        let cin = viewModel.config.schedule.clockin
        let cout = viewModel.config.schedule.clockout
        let cinEnd = addMinutes(delay / 60, to: cin)
        let coutEnd = addMinutes(delay / 60, to: cout)
        return "\(cin) – \(cinEnd) / \(cout) – \(coutEnd)"
    }

    private var wakeScheduleSubtitle: String {
        viewModel.wakeSyncState.message ?? "Requires AC power and admin permission."
    }

    private var isScheduleEditingEnabled: Bool {
        viewModel.config.autopunchEnabled && !viewModel.wakeSyncState.isApplying
    }

    private func addMinutes(_ minutes: Int, to time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let h = parts.indices.contains(0) ? parts[0] : 0
        let m = parts.indices.contains(1) ? parts[1] : 0
        let total = h * 60 + m + minutes
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    private func durationText(_ seconds: Int) -> String {
        let normalized = max(0, seconds)
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: AppStyle.Spacing.md)

            control()
        }
        .frame(minHeight: AppStyle.Layout.settingsRowHeight)
        .padding(.horizontal, AppStyle.Spacing.cardPadding)
        .opacity(isEnabled ? 1 : AppStyle.Opacity.disabled)
        .disabled(!isEnabled)
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
