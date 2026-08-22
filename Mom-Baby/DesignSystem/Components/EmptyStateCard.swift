import SwiftUI

@MainActor
struct EmptyStateCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.primaryText)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: AppMetrics.minimumTapTarget)
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card))
    }
}
