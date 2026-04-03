import SwiftUI

struct PunchButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppStyle.Spacing.xxl)
            .padding(.vertical, AppStyle.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.Radius.medium, style: .continuous)
                    .fill(backgroundColor(configuration))
            )
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? AppStyle.Layout.punchButtonScale : 1)
            .animation(AppStyle.Animation.micro, value: configuration.isPressed)
    }

    private func backgroundColor(_ configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(configuration.isPressed ? AppStyle.Opacity.pressed : AppStyle.Opacity.normal)
        }

        return Color.black.opacity(configuration.isPressed ? AppStyle.Opacity.pressed : AppStyle.Opacity.normal)
    }

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(AppStyle.Opacity.foreground)
        }

        return Color.white.opacity(AppStyle.Opacity.foreground)
    }
}

#Preview("Light") {
    Button(action: {}) {
        HStack(spacing: AppStyle.Spacing.lg) {
            Image(systemName: "hand.tap.fill")
                .font(AppStyle.Font.bodyMedium)
            Text("Clock In Now")
                .font(AppStyle.Font.bodyMedium)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(PunchButtonStyle())
    .padding()
    .frame(width: AppStyle.Layout.panelWidth)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    Button(action: {}) {
        HStack(spacing: AppStyle.Spacing.lg) {
            Image(systemName: "hand.tap.fill")
                .font(AppStyle.Font.bodyMedium)
            Text("Clock In Now")
                .font(AppStyle.Font.bodyMedium)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(PunchButtonStyle())
    .padding()
    .frame(width: AppStyle.Layout.panelWidth)
    .preferredColorScheme(.dark)
}
