import SwiftUI

struct StatusMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: AppStyle.Spacing.sm) {
            Text(title)
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
        StatusMetric(title: "Clock In", value: "09:03")
        StatusMetric(title: "Clock Out", value: "--:--")
    }
    .padding()
    .frame(width: AppStyle.Layout.panelWidth)
}
