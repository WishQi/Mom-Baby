import SwiftUI

@MainActor
enum AppColors {
    static let background = Color("AppBackground")
    static let surface = Color("AppSurface")
    static let tintedSurface = Color("AppTintedSurface")
    static let primaryText = Color("AppPrimaryText")
    static let secondaryText = Color("AppSecondaryText")
    static let mutedText = Color("AppMutedText")
    static let accent = Color.accentColor
    static let accentSoft = Color("AppAccentSoft")
    static let border = Color("AppBorder")
    static let peach = Color("AppPeach")
    static let gold = Color("AppGold")
    static let blue = Color("AppBlue")
    static let warning = Color(red: 0.82, green: 0.48, blue: 0.12)
}

@MainActor
enum AppTypography {
    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let largeTitle = Font.system(.title, design: .serif, weight: .semibold)
    static let title = Font.system(.title2, design: .serif, weight: .medium)
    static let headline = Font.headline.weight(.semibold)
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let eyebrow = Font.caption.weight(.bold)
}

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let section: CGFloat = 20
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
}

enum AppCornerRadius {
    static let control: CGFloat = 13
    static let largeCard: CGFloat = 16
    static let button: CGFloat = 17
    static let card: CGFloat = 22
    static let hero: CGFloat = 26
    static let illustration: CGFloat = 34
}

enum AppMetrics {
    static let minimumTapTarget: CGFloat = 44
    static let contentInset: CGFloat = 20
    static let primaryButtonHeight: CGFloat = 52
}
