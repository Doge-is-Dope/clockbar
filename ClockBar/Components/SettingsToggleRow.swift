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
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))

            Spacer(minLength: 10)

            trailing

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    VStack(spacing: 4) {
        SettingsToggleRow(title: "Auto-punch", isOn: .constant(true))
    }
    .padding()
    .frame(width: 332)
}
