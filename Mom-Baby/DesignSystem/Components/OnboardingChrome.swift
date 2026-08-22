import SwiftUI

@MainActor
struct OnboardingHeader: View {
    let title: String
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.primaryText)

            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                }
                Spacer()
            }
        }
        .frame(height: 58)
    }
}

@MainActor
struct OnboardingProgress: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index == step ? AppColors.accent : AppColors.mutedText.opacity(0.28))
                    .frame(width: index == step ? 20 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(step) 步，共 \(total) 步")
    }
}

@MainActor
struct StickyPrimaryAction<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.top, AppSpacing.medium)
            .padding(.bottom, AppSpacing.large)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.35)
            }
    }
}
