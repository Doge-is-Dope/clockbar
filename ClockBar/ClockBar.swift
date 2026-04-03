import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: StatusViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summarySection
            rowDivider
            actionsSection
            rowDivider
            automationSection
            rowDivider
            sessionActionRow
            rowDivider
            quitRow
        }
        .padding(.vertical, AppStyle.Spacing.xs)
        .frame(width: AppStyle.Layout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summarySection: some View {
        VStack(alignment: .trailing, spacing: AppStyle.Spacing.xl) {
            HStack(spacing: 0) {
                StatusMetric(
                    title: "Clock In",
                    value: vm.status?.clockIn ?? "--:--"
                )

                StatusMetric(
                    title: "Clock Out",
                    value: vm.status?.clockOut ?? "--:--"
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
            }
        }
        .padding(.horizontal, AppStyle.Spacing.xxl)
        .padding(.vertical, AppStyle.Spacing.lg)
    }

    private var actionsSection: some View {
        VStack(spacing: AppStyle.Spacing.xs) {
            Button(action: { vm.punchNow() }) {
                HStack(spacing: AppStyle.Spacing.lg) {
                    if vm.isPunching {
                        Image(systemName: "progress.indicator")
                            .font(AppStyle.Font.bodyMedium)
                            .symbolEffect(.rotate, isActive: true)
                    }

                    Text(vm.isPunching ? "Punching…" : punchButtonTitle)
                        .font(AppStyle.Font.bodyMedium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PunchButtonStyle())
            .disabled(vm.isPunching)
            .padding(.horizontal, AppStyle.Spacing.xs)
            .padding(.bottom, AppStyle.Spacing.xs)

            VStack(spacing: 0) {
                MenuPanelButton(action: toggleScheduleExpanded) { _ in
                    HStack(spacing: AppStyle.Spacing.lg) {
                        Text("Schedule")
                            .font(AppStyle.Font.body)
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Spacer(minLength: AppStyle.Spacing.md)

                        Text("\(vm.config.schedule.clockin) - \(vm.config.schedule.clockout)")
                            .font(AppStyle.Font.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(AppStyle.Font.chevron)
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .rotationEffect(.degrees(vm.scheduleExpanded ? 90 : 0))
                            .animation(AppStyle.Animation.standard, value: vm.scheduleExpanded)
                    }
                }

                VStack(spacing: 0) {
                    ScheduleRow(
                        title: "Clock In",
                        time: Binding(
                            get: { vm.config.schedule.clockin },
                            set: { vm.updateSchedule(clockIn: $0) }
                        ),
                        onChanged: {}
                    )

                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(AppStyle.Opacity.separator))
                        .frame(height: AppStyle.Layout.dividerHeight)

                    ScheduleRow(
                        title: "Clock Out",
                        time: Binding(
                            get: { vm.config.schedule.clockout },
                            set: { vm.updateSchedule(clockOut: $0) }
                        ),
                        onChanged: {}
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                        .fill(editorFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(AppStyle.Opacity.separator), lineWidth: 1)
                )
                .padding(.horizontal, AppStyle.Spacing.md)
                .padding(.top, AppStyle.Spacing.xs)
                .frame(maxHeight: vm.scheduleExpanded ? .none : 0, alignment: .top)
                .clipped()
                .opacity(vm.scheduleExpanded ? 1 : 0)
                .allowsHitTesting(vm.scheduleExpanded)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.md)
        .padding(.vertical, AppStyle.Spacing.sm)
    }

    private var sessionActionRow: some View {
        Group {
            if vm.isAuthenticated {
                MenuPanelButton(action: { vm.signOut() }, hoverColor: .red.opacity(AppStyle.Opacity.destructiveHover)) { _ in
                    HStack(spacing: AppStyle.Spacing.lg) {
                        Text("Sign Out")
                            .font(AppStyle.Font.body)
                        Spacer(minLength: AppStyle.Spacing.md)
                    }
                    .foregroundStyle(.red)
                }
            } else {
                MenuPanelButton(action: { vm.beginAuthentication() }, isEnabled: !vm.isAuthenticating) { _ in
                    HStack(spacing: AppStyle.Spacing.lg) {
                        Text(vm.isAuthenticating ? "Signing In…" : "Sign In")
                            .font(AppStyle.Font.body)
                        Spacer(minLength: AppStyle.Spacing.md)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppStyle.Spacing.md)
        .padding(.vertical, AppStyle.Spacing.sm)
    }

    private var automationSection: some View {
        VStack(spacing: AppStyle.Spacing.xs) {
            MenuPanelToggleRow(
                title: "Auto-punch",
                isOn: Binding(
                    get: { vm.config.autopunchEnabled },
                    set: { vm.setAutopunchEnabled($0) }
                )
            )

            Text("Automatically clocks in and out at the scheduled times on workdays.")
                .font(AppStyle.Font.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppStyle.Spacing.md)
        .padding(.vertical, AppStyle.Spacing.sm)
    }

    private var quitRow: some View {
        MenuPanelButton(action: { NSApp.terminate(nil) }) { _ in
            HStack(spacing: AppStyle.Spacing.lg) {
                Text("Quit")
                    .font(AppStyle.Font.body)
                Spacer(minLength: AppStyle.Spacing.md)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppStyle.Spacing.md)
        .padding(.vertical, AppStyle.Spacing.sm)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(AppStyle.Opacity.separator))
            .frame(height: AppStyle.Layout.dividerHeight)
            .padding(.horizontal, AppStyle.Spacing.md)
    }

    private var authStatusText: String? {
        let text = vm.authStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var errorText: String? {
        vm.bannerText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var punchButtonTitle: String {
        if vm.status?.clockIn == nil {
            return "Clock In Now"
        }

        if vm.status?.clockOut == nil {
            return "Clock Out Now"
        }

        return "Punch Now"
    }

    private var editorFill: Color {
        Color(nsColor: colorScheme == .dark ? .quaternaryLabelColor : .windowBackgroundColor)
            .opacity(colorScheme == .dark ? AppStyle.Opacity.editorFillDark : AppStyle.Opacity.editorFillLight)
    }

    private func toggleScheduleExpanded() {
        withAnimation(AppStyle.Animation.standard) {
            vm.scheduleExpanded.toggle()
        }
    }
}

private struct MenuPanelButton<Label: View>: View {
    let action: () -> Void
    var isEnabled = true
    var hoverColor: Color = Color(nsColor: .labelColor).opacity(AppStyle.Opacity.hover)
    @ViewBuilder let label: (Bool) -> Label

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label(isHighlighted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppStyle.Spacing.sm)
                .frame(minHeight: AppStyle.Layout.menuItemMinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                .fill(backgroundColor)
        )
        .opacity(isEnabled ? 1 : AppStyle.Opacity.disabled)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var isHighlighted: Bool {
        isEnabled && (isHovered || isPressed)
    }

    private var backgroundColor: Color {
        isHighlighted ? hoverColor : .clear
    }
}

private struct MenuPanelToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.lg) {
            Text(title)
                .font(AppStyle.Font.body)
                .foregroundStyle(Color(nsColor: .labelColor))

            Spacer(minLength: AppStyle.Spacing.md)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color(nsColor: .labelColor))
                .labelsHidden()
        }
        .padding(.horizontal, AppStyle.Spacing.sm)
        .frame(minHeight: AppStyle.Layout.menuItemMinHeight)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                .fill(isHovered ? Color(nsColor: .labelColor).opacity(AppStyle.Opacity.hover) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { isHovered = $0 }
    }
}

@main
@MainActor
struct ClockBarApp: App {
    @StateObject private var vm: StatusViewModel

    init() {
        NotificationManager.shared.setup()
        let viewModel = StatusViewModel()
        viewModel.start()
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(vm: vm)
        } label: {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                Image(systemName: vm.bannerText != nil ? "clock.badge.exclamationmark" : "clock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

#Preview("Light") {
    ContentView(vm: StatusViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(vm: StatusViewModel())
        .preferredColorScheme(.dark)
}
