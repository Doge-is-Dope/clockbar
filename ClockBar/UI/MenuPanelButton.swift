import SwiftUI

struct MenuPanelButton<Label: View>: View {
    let action: () -> Void
    var isEnabled = true
    var hoverColor: Color = AppStyle.Palette.label.opacity(AppStyle.Opacity.hover)
    @ViewBuilder let label: (Bool) -> Label

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label(isHighlighted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: AppStyle.Layout.menuRowMinHeight, alignment: .center)
                .padding(.horizontal, AppStyle.Spacing.md)
                .padding(.vertical, AppStyle.Spacing.xs)
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
