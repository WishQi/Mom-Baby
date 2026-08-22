import SwiftUI

@MainActor
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppMetrics.primaryButtonHeight)
            .foregroundStyle(.white)
            .background(isEnabled ? AppColors.accent : AppColors.mutedText.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous))
            .shadow(
                color: AppColors.accent.opacity(isEnabled ? 0.18 : 0),
                radius: 11,
                y: 10
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .frame(minHeight: AppMetrics.minimumTapTarget)
    }
}

#Preview {
    PrimaryButton(title: "开始使用", symbol: "chevron.right") {}
        .padding()
        .background(AppColors.background)
}
