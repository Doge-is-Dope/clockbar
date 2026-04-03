import SwiftUI

struct SettingsToggleRow<Trailing: View>: View {
    @ViewBuilder private let trailing: Trailing
    let title: String
    @Binding var isOn: Bool

    init(
        title: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self._isOn = isOn
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.lg) {
            Text(title)
                .font(AppStyle.Font.subheadlineMedium)

            Spacer(minLength: AppStyle.Spacing.lg)

            trailing

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    VStack(spacing: AppStyle.Spacing.xs) {
        SettingsToggleRow(title: "Auto-punch", isOn: .constant(true))
    }
    .padding()
    .frame(width: AppStyle.Layout.panelWidth)
}
