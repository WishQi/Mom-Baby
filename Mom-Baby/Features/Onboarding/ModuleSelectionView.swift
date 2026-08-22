import Domain
import SwiftUI

@MainActor
struct ModuleSelectionView: View {
    @Bindable var model: OnboardingModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingHeader(title: "想记录什么？", onBack: model.moveBack)
                OnboardingProgress(step: 3, total: 4)

                Text("亲喂、吸奶和奶瓶可以分别选择。首页最多展示四个快捷入口，其余仍可从全局记录打开。")
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, AppSpacing.large)
                    .padding(.horizontal, AppSpacing.small)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(HomeModule.onboardingChoices, id: \.rawValue) { module in
                        ModuleChoiceCard(
                            module: module,
                            isSelected: model.selectedModules.contains(module)
                        ) {
                            model.toggle(module)
                        }
                    }
                }
                .padding(.top, AppSpacing.large)

                if model.requiresAdultLactationConsent {
                    AdultLactationConsentCard(model: model)
                        .padding(.top, AppSpacing.large)
                }

                Button("跳过选择，使用推荐的四个入口") {
                    model.useDefaultModules()
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(minHeight: AppMetrics.minimumTapTarget)
                .padding(.top, AppSpacing.small)
            }
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .disabled(model.isSubmitting)
        .scrollDisabled(model.isSubmitting)
        .safeAreaInset(edge: .bottom) {
            StickyPrimaryAction {
                PrimaryButton(
                    title: "进入\(model.normalizedNickname)的今日",
                    isEnabled: model.canComplete,
                    isLoading: model.isSubmitting
                ) {
                    Task { await model.complete() }
                }
                .accessibilityIdentifier("onboarding.modules.complete")
            }
        }
        .accessibilityIdentifier("onboarding.modules")
    }
}

@MainActor
private struct ModuleChoiceCard: View {
    let module: HomeModule
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: module.systemImage)
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 42, height: 42)
                    .background(module.softColor)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                Text(module.displayName)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.top, AppSpacing.medium)

                Text(module.supportingText)
                    .font(.caption2)
                    .foregroundStyle(AppColors.mutedText)
                    .lineLimit(2)
                    .padding(.top, AppSpacing.xSmall)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .padding(15)
            .background(isSelected ? AppColors.tintedSurface : AppColors.surface)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? AppColors.accent : AppColors.mutedText.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .stroke(isSelected ? AppColors.border : AppColors.mutedText.opacity(0.20), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .shadow(color: AppColors.primaryText.opacity(isSelected ? 0.07 : 0.03), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}

@MainActor
private struct AdultLactationConsentCard: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label("成人哺乳信息需要独立确认", systemImage: "person.crop.circle.badge.checkmark")
                .font(.callout.weight(.bold))
                .foregroundStyle(AppColors.primaryText)

            Text("左右侧与吸奶量属于当前受信任成人本人。确认表示你也是这些记录对应的哺乳者，不表示 App 已核验身份。")
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(3)

            Button {
                model.toggleAdultLactationConsent()
            } label: {
                HStack(spacing: AppSpacing.small) {
                    Image(systemName: model.adultLactationConsentGranted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(AppColors.accent)
                    Text("我已阅读并单独同意")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                    Spacer()
                }
                .frame(minHeight: AppMetrics.minimumTapTarget)
            }
            .buttonStyle(.plain)

            Button("查看《成人哺乳与吸奶信息处理说明》", action: model.showAdultNotice)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .buttonStyle(.plain)
        }
        .padding(AppSpacing.large)
        .background(AppColors.tintedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
