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
        .padding(.vertical, 8)
        .frame(width: 300)
    }

    private var summarySection: some View {
        VStack(alignment: .trailing, spacing: 12) {
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
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button(action: { vm.punchNow() }) {
                HStack(spacing: 10) {
                    if vm.isPunching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14, weight: .medium))
                    }

                    Text(vm.isPunching ? "Punching…" : punchButtonTitle)
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PunchButtonStyle())
            .disabled(vm.isPunching)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                MenuPanelButton(action: toggleScheduleExpanded) { _ in
                    HStack(spacing: 10) {
                        Text("Schedule")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Spacer(minLength: 8)

                        Text("\(vm.config.schedule.clockin) - \(vm.config.schedule.clockout)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .rotationEffect(.degrees(vm.scheduleExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.25), value: vm.scheduleExpanded)
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
                        .fill(Color(nsColor: .separatorColor).opacity(0.55))
                        .frame(height: 0.5)

                    ScheduleRow(
                        title: "Clock Out",
                        time: Binding(
                            get: { vm.config.schedule.clockout },
                            set: { vm.updateSchedule(clockOut: $0) }
                        ),
                        onChanged: {}
                    )
                }
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(editorFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .frame(maxHeight: vm.scheduleExpanded ? .none : 0, alignment: .top)
                .clipped()
                .opacity(vm.scheduleExpanded ? 1 : 0)
                .allowsHitTesting(vm.scheduleExpanded)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var sessionActionRow: some View {
        Group {
            if vm.isAuthenticated {
                MenuPanelButton(action: { vm.signOut() }) { _ in
                    HStack(spacing: 10) {
                        Text("Sign Out")
                            .font(.system(size: 14, weight: .regular))
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(.red)
                }
            } else {
                MenuPanelButton(action: { vm.beginAuthentication() }, isEnabled: !vm.isAuthenticating) { _ in
                    HStack(spacing: 10) {
                        Text(vm.isAuthenticating ? "Signing In…" : "Sign In")
                            .font(.system(size: 14, weight: .regular))
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var automationSection: some View {
        VStack(spacing: 4) {
            MenuPanelToggleRow(
                title: "Auto-punch",
                isOn: Binding(
                    get: { vm.config.autopunchEnabled },
                    set: { vm.setAutopunchEnabled($0) }
                )
            )

            Text("Automatically clocks in and out at the scheduled times on workdays.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var quitRow: some View {
        MenuPanelButton(action: { NSApp.terminate(nil) }) { _ in
            HStack(spacing: 10) {
                Text("Quit ClockBar")
                    .font(.system(size: 14, weight: .regular))
                Spacer(minLength: 8)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
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
            .opacity(colorScheme == .dark ? 0.35 : 0.96)
    }

    private func toggleScheduleExpanded() {
        withAnimation(.easeInOut(duration: 0.25)) {
            vm.scheduleExpanded.toggle()
        }
    }
}

private struct MenuPanelButton<Label: View>: View {
    let action: () -> Void
    var isEnabled = true
    @ViewBuilder let label: (Bool) -> Label

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label(isHighlighted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor)
        )
        .opacity(isEnabled ? 1 : 0.55)
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
        isHighlighted ? Color(nsColor: .labelColor).opacity(0.08) : .clear
    }
}

private struct MenuPanelToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(nsColor: .labelColor))

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color(nsColor: .labelColor))
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? Color(nsColor: .labelColor).opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
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
                Image(systemName: "clock")
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
