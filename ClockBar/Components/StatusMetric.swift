import SwiftUI

struct StatusMetric: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        VStack(spacing: AppStyle.Spacing.sm) {
            Label {
                Text(title)
            } icon: {
                if !icon.isEmpty {
                    Image(systemName: icon)
                }
            }
            .font(AppStyle.Font.metricTitle)
            .foregroundStyle(.secondary)

            Text(value)
                .font(AppStyle.Font.largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HStack(spacing: 0) {
        StatusMetric(title: "Clock In", icon: "arrow.down.to.line", value: "09:03")
        StatusMetric(title: "Clock Out", icon: "arrow.up.to.line", value: "--:--")
    }
    .padding()
    .frame(width: AppStyle.Layout.panelWidth)
}
