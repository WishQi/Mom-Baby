import Domain
import SwiftUI

@MainActor
struct OnboardingFlowView: View {
    @State private var model: OnboardingModel

    init(
        completeOperation: @escaping OnboardingModel.CompleteOperation
    ) {
        _model = State(
            initialValue: OnboardingModel(completeOperation: completeOperation)
        )
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            AppColors.background.ignoresSafeArea()

            switch model.step {
            case .welcome:
                WelcomeView(model: model)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .consent:
                ConsentView(model: model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .profile:
                BabyProfileView(model: model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .modules:
                ModuleSelectionView(model: model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: model.step)
        .sheet(item: $model.presentedNotice) { notice in
            PolicyNoticeView(notice: notice)
        }
        .alert(
            "暂时无法保存",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .accessibilityIdentifier("onboarding.root")
    }
}

@MainActor
private struct WelcomeView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Button("跳过介绍") {
                            model.moveForward()
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AppMetrics.minimumTapTarget)
                    }

                    WelcomeIllustration()
                        .frame(height: min(330, proxy.size.height * 0.42))
                        .padding(.top, AppSpacing.small)

                    Text("MOM-BABY")
                        .font(AppTypography.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(AppColors.accent)
                        .padding(.top, AppSpacing.xLarge)

                    Text("每一次照护，\n都值得被轻轻记住")
                        .font(AppTypography.display)
                        .tracking(-0.8)
                        .foregroundStyle(AppColors.primaryText)
                        .padding(.top, AppSpacing.xSmall)

                    Text("几秒记录喂养、尿布和成长。无需账号或网络，数据保存在 App 中。")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineSpacing(5)
                        .padding(.top, AppSpacing.medium)

                    Spacer(minLength: AppSpacing.xxLarge)

                    PrimaryButton(
                        title: "开始使用",
                        symbol: "chevron.right"
                    ) {
                        model.moveForward()
                    }
                    .accessibilityIdentifier("onboarding.welcome.start")

                    Label("默认私密 · 不含广告与公开动态", systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(AppColors.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.medium)
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.bottom, AppSpacing.xLarge)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("onboarding.welcome")
    }
}

@MainActor
private struct WelcomeIllustration: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [AppColors.accentSoft, AppColors.background, AppColors.peach],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: 58, height: 58)
                    .offset(x: proxy.size.width * 0.23, y: -proxy.size.height * 0.30)

                Circle()
                    .fill(AppColors.gold.opacity(0.9))
                    .frame(width: 58, height: 58)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.height * 0.22)

                Ellipse()
                    .fill(AppColors.accent.opacity(0.16))
                    .frame(width: 150, height: 210)
                    .rotationEffect(.degrees(28))
                    .offset(x: -proxy.size.width * 0.39, y: proxy.size.height * 0.46)

                Ellipse()
                    .fill(AppColors.secondaryText.opacity(0.13))
                    .frame(width: 150, height: 210)
                    .rotationEffect(.degrees(-18))
                    .offset(x: proxy.size.width * 0.45, y: proxy.size.height * 0.47)

                Circle()
                    .stroke(AppColors.accent.opacity(0.22), lineWidth: 1)
                    .frame(width: min(proxy.size.width * 0.60, 204))

                ZStack {
                    Ellipse()
                        .fill(AppColors.peach)
                        .frame(width: 150, height: 114)
                        .shadow(color: AppColors.primaryText.opacity(0.10), radius: 16, y: 16)
                    Text("˘ ᴗ ˘")
                        .font(.system(size: 17))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.46, green: 0.40, blue: 0.37))
                }
                .rotationEffect(.degrees(-7))

                Circle()
                    .fill(AppColors.accent.opacity(0.85))
                    .frame(width: 9, height: 9)
                    .offset(x: -proxy.size.width * 0.20, y: -proxy.size.height * 0.14)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.illustration, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private struct ConsentView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingHeader(title: "使用前确认", onBack: model.moveBack)
                OnboardingProgress(step: 1, total: 4)

                BoundaryNoticeCard()
                    .padding(.top, AppSpacing.xLarge)

                VStack(spacing: 10) {
                    ConsentChoiceRow(
                        isSelected: model.guardianDeclared,
                        title: "我是宝宝的父母或其他法定监护人",
                        detail: "这是设备侧自我声明，Mom-Baby 不会把它描述成已核验身份。"
                    ) {
                        model.guardianDeclared.toggle()
                    }

                    ConsentChoiceRow(
                        isSelected: model.childConsentGranted,
                        title: "单独同意处理宝宝的必要信息",
                        detail: "用于建立档案及在本机保存由你主动创建的照护记录。"
                    ) {
                        model.childConsentGranted.toggle()
                    }
                }
                .padding(.top, AppSpacing.large)

                Button(action: model.showChildNotice) {
                    Text("查看《儿童个人信息处理说明》")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AppMetrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.childNotice == nil)

                if let policyLoadFailure = model.policyLoadFailure {
                    Text(policyLoadFailure)
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .safeAreaInset(edge: .bottom) {
            StickyPrimaryAction {
                PrimaryButton(
                    title: "同意并继续",
                    isEnabled: model.canContinueFromConsent
                ) {
                    model.moveForward()
                }
                .accessibilityIdentifier("onboarding.consent.continue")
            }
        }
        .accessibilityIdentifier("onboarding.consent")
    }
}

@MainActor
private struct BoundaryNoticeCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: "shield")
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: 38, height: 38)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("一次安装，一个受信任成人")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Text("无需注册也能在本机使用。任何能解锁设备和 App 的人都可能查看或修改当前安装中的数据。")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(3)
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tintedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.largeCard, style: .continuous)
                .stroke(AppColors.accentSoft, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.largeCard, style: .continuous))
    }
}

@MainActor
private struct ConsentChoiceRow: View {
    let isSelected: Bool
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 24, height: 24)
                    .background(isSelected ? AppColors.accent : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? AppColors.accent : AppColors.mutedText, lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppColors.mutedText)
                        .lineSpacing(3)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.tintedSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColors.border : AppColors.accentSoft.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}

@MainActor
private struct PolicyNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    let notice: OnboardingPolicyNotice

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(notice.body)
                    .font(.body)
                    .foregroundStyle(AppColors.primaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.xLarge)
            }
            .background(AppColors.surface)
            .navigationTitle(notice.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
