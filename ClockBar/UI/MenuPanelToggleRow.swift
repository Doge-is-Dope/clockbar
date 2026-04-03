import SwiftUI

struct MenuPanelToggleRow: View {
    let title: String
    var icon: String = ""
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
        }
        .padding(.horizontal, AppStyle.Spacing.sm)
        .frame(minHeight: AppStyle.Layout.menuItemMinHeight)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.small, style: .continuous)
                .fill(
                    isHovered
                        ? Color(nsColor: .labelColor).opacity(AppStyle.Opacity.hover)
                        : .clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { isHovered = $0 }
    }
}
