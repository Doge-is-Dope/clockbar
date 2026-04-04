import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StatusViewModel
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
            sessionActionRow
            rowDivider
            quitRow
        }
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
        Group {
            if viewModel.isAuthenticated {
                MenuPanelButton(
                    action: { viewModel.signOut() },
                    hoverColor: .red.opacity(AppStyle.Opacity.destructiveHover)
                ) { _ in
                    HStack(spacing: AppStyle.Spacing.lg) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(AppStyle.Font.body)
                        Spacer(minLength: AppStyle.Spacing.md)
                    }
                    .foregroundStyle(.red)
                }
            } else {
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
            }
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
                            if !newValue {
                                viewModel.scheduleExpanded = false
                            }
                        }
                    }
                )
            )

            if viewModel.config.autopunchEnabled {
                VStack(spacing: 0) {
                    MenuPanelButton(action: toggleScheduleExpanded) { _ in
                        HStack(spacing: AppStyle.Spacing.lg) {
                            Label("Schedule", systemImage: "calendar")
                                .font(AppStyle.Font.body)
                                .foregroundStyle(Color(nsColor: .labelColor))

                            Spacer(minLength: AppStyle.Spacing.md)

                            Text(
                                "\(viewModel.config.schedule.clockin) - \(viewModel.config.schedule.clockout)"
                            )
                            .font(AppStyle.Font.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(AppStyle.Font.chevron)
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .rotationEffect(.degrees(viewModel.scheduleExpanded ? 90 : 0))
                                .animation(
                                    AppStyle.Animation.standard,
                                    value: viewModel.scheduleExpanded
                                )
                        }
                    }

                    Text("Skips weekends and public holidays.")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, AppStyle.Spacing.md)

                    VStack(spacing: 0) {
                        ScheduleRow(
                            title: "Clock In",
                            time: Binding(
                                get: { viewModel.config.schedule.clockin },
                                set: { viewModel.updateSchedule(clockIn: $0) }
                            )
                        )

                        Rectangle()
                            .fill(
                                Color(nsColor: .separatorColor)
                                    .opacity(AppStyle.Opacity.separator)
                            )
                            .frame(height: AppStyle.Layout.dividerHeight)

                        ScheduleRow(
                            title: "Clock Out",
                            time: Binding(
                                get: { viewModel.config.schedule.clockout },
                                set: { viewModel.updateSchedule(clockOut: $0) }
                            )
                        )
                    }
                    .padding(.horizontal, AppStyle.Spacing.xl)
                    .background(
                        RoundedRectangle(
                            cornerRadius: AppStyle.Radius.small,
                            style: .continuous
                        )
                        .fill(editorFill)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: AppStyle.Radius.small,
                            style: .continuous
                        )
                        .strokeBorder(
                            Color(nsColor: .separatorColor)
                                .opacity(AppStyle.Opacity.separator),
                            lineWidth: AppStyle.Layout.borderWidth
                        )
                    )
                    .padding(.horizontal, AppStyle.Spacing.md)
                    .padding(.top, AppStyle.Spacing.xs)
                    .frame(maxHeight: viewModel.scheduleExpanded ? .none : 0, alignment: .top)
                    .clipped()
                    .opacity(viewModel.scheduleExpanded ? 1 : 0)
                    .allowsHitTesting(viewModel.scheduleExpanded)
                }

                MenuPanelToggleRow(
                    title: "Wake on Schedule",
                    icon: "powersleep",
                    isOn: Binding(
                        get: { viewModel.config.wakeEnabled },
                        set: { _ in viewModel.toggleWake() }
                    )
                )

                Text("Wake your Mac for auto-punch. Requires AC power.")
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

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(AppStyle.Opacity.separator))
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

    private var editorFill: Color {
        Color(
            nsColor: colorScheme == .dark ? .quaternaryLabelColor : .windowBackgroundColor
        )
        .opacity(
            colorScheme == .dark
                ? AppStyle.Opacity.editorFillDark
                : AppStyle.Opacity.editorFillLight
        )
    }

    private func toggleScheduleExpanded() {
        withAnimation(AppStyle.Animation.standard) {
            viewModel.scheduleExpanded.toggle()
        }
    }
}

#Preview("Light") {
    ContentView(viewModel: StatusViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(viewModel: StatusViewModel())
        .preferredColorScheme(.dark)
}
