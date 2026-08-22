import SwiftUI

@MainActor
struct FeaturePlaceholderView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .combine)
    }
}
