import SwiftUI

struct MenuPanelButton<Label: View>: View {
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
