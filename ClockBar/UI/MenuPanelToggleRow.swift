import SwiftUI

struct MenuPanelToggleRow: View {
    let title: String
    var icon: String = ""
    var isEnabled = true
    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.lg) {
            Label {
                Text(title)
            } icon: {
                if !icon.isEmpty {
                    Image(systemName: icon)
                }
            }
            .font(AppStyle.Font.body)
            .foregroundStyle(Color(nsColor: .labelColor))

            Spacer(minLength: AppStyle.Spacing.md)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color(nsColor: .labelColor))
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(AppStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                .fill(
                    isHovered && isEnabled
                        ? Color(nsColor: .labelColor).opacity(AppStyle.Opacity.hover)
                        : .clear
                )
        )
        .opacity(isEnabled ? 1 : AppStyle.Opacity.disabled)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            isOn.toggle()
        }
        .onHover { isHovered = $0 }
    }
}
