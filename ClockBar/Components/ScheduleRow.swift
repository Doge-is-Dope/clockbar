import AppKit
import Combine
import SwiftUI

struct ScheduleRow: View {
    let title: String
    @Binding var time: String
    let onChanged: () -> Void

    @State private var selection = Date()

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.xl) {
            Text(title)
                .font(AppStyle.Font.subheadlineMedium)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            DatePicker(
                "",
                selection: Binding(
                    get: { selection },
                    set: { newValue in
                        selection = newValue
                        persist(newValue)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
        }
        .padding(.vertical, AppStyle.Spacing.xl)
        .frame(minHeight: AppStyle.Layout.scheduleRowMinHeight, alignment: .center)
        .onAppear {
            selection = date(from: time)
        }
        .onReceive(Just(time).removeDuplicates()) { newValue in
            let parsed = date(from: newValue)
            if !calendar.isDate(selection, equalTo: parsed, toGranularity: .minute) {
                selection = parsed
            }
        }
    }

    private func persist(_ value: Date) {
        let newTime = Self.storageFormatter.string(from: value)
        guard newTime != time else { return }
        time = newTime
        onChanged()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func date(from value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        let hour = parts.indices.contains(0) ? parts[0] : 0
        let minute = parts.indices.contains(1) ? parts[1] : 0

        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay)
            ?? startOfDay
    }

    private static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview("Light") {
    VStack(spacing: 0) {
        ScheduleRow(title: "Clock In", time: .constant("09:00"), onChanged: {})
        Divider()
        ScheduleRow(title: "Clock Out", time: .constant("18:00"), onChanged: {})
    }
    .padding(AppStyle.Spacing.xl)
    .frame(width: AppStyle.Layout.panelWidth)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: 0) {
        ScheduleRow(title: "Clock In", time: .constant("09:00"), onChanged: {})
        Divider()
        ScheduleRow(title: "Clock Out", time: .constant("18:00"), onChanged: {})
    }
    .padding(AppStyle.Spacing.xl)
    .frame(width: AppStyle.Layout.panelWidth)
    .preferredColorScheme(.dark)
}
