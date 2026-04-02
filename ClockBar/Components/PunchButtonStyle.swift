import SwiftUI

struct PunchButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor(configuration))
            )
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColor(_ configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(configuration.isPressed ? 0.78 : 0.84)
        }

        return Color.black.opacity(configuration.isPressed ? 0.78 : 0.84)
    }

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(0.96)
        }

        return Color.white.opacity(0.96)
    }
}

#Preview("Light") {
    Button(action: {}) {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Clock In Now")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("Auto on")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(PunchButtonStyle())
    .padding()
    .frame(width: 332)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    Button(action: {}) {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Clock In Now")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("Auto on")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(PunchButtonStyle())
    .padding()
    .frame(width: 332)
    .preferredColorScheme(.dark)
}
