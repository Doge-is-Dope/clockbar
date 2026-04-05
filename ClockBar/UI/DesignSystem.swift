import SwiftUI

enum AppStyle {

    // MARK: - Typography

    enum Font {
        static let largeTitle: SwiftUI.Font = .system(size: 28, weight: .semibold, design: .rounded)
        static let sectionTitle: SwiftUI.Font = .system(size: 14, weight: .semibold)
        static let icon: SwiftUI.Font = .system(size: 13, weight: .medium)
        static let body: SwiftUI.Font = .system(size: 14, weight: .regular)
        static let bodyMedium: SwiftUI.Font = .system(size: 14, weight: .medium)
        static let subheadline: SwiftUI.Font = .system(size: 12, weight: .regular)
        static let subheadlineMedium: SwiftUI.Font = .system(size: 12, weight: .medium)
        static let caption: SwiftUI.Font = .system(size: 10, weight: .regular)
        static let metricTitle: SwiftUI.Font = .system(size: 11.5, weight: .medium)
        static let chevron: SwiftUI.Font = .system(size: 12, weight: .semibold)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        static let sectionGap: CGFloat = 24
        static let cardPadding: CGFloat = 12
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 10
        static let medium: CGFloat = 14
    }

    // MARK: - Opacity

    enum Opacity {
        static let cardFill: Double = 0.06
        static let hover: Double = 0.08
        static let destructiveHover: Double = 0.12
        static let separator: Double = 0.7
        static let disabled: Double = 0.55
        static let pressed: Double = 0.78
        static let normal: Double = 0.84
        static let foreground: Double = 0.96
        static let editorFillDark: Double = 0.35
        static let editorFillLight: Double = 0.96
    }

    // MARK: - Palette

    enum Palette {
        static let label = Color(nsColor: .labelColor)
        static let separator = Color(nsColor: .separatorColor)
    }

    // MARK: - Animation

    enum Animation {
        static let micro: SwiftUI.Animation = .easeOut(duration: 0.14)
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.25)
    }

    // MARK: - Layout

    enum Layout {
        static let panelWidth: CGFloat = 280
        static let menuItemMinHeight: CGFloat = 30
        static let scheduleRowMinHeight: CGFloat = 34
        static let settingsRowHeight: CGFloat = 44
        static let iconBackgroundSize: CGFloat = 28
        static let durationLabelWidth: CGFloat = 36
        static let settingsMinWidth: CGFloat = 480
        static let settingsIdealWidth: CGFloat = 520
        static let dividerHeight: CGFloat = 1
        static let punchButtonScale: CGFloat = 0.985
        static let borderWidth: CGFloat = 1
        static let loginWindowSize = NSRect(x: 0, y: 0, width: 480, height: 680)
    }
}
