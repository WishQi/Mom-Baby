import Domain
import SwiftUI

@MainActor
struct BabyProfileView: View {
    @Bindable var model: OnboardingModel
    @State private var showsBirthDatePicker = false
    @State private var draftBirthDate = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingHeader(title: "宝宝建档", onBack: model.moveBack)
                OnboardingProgress(step: 2, total: 4)

                avatar
                    .padding(.top, AppSpacing.xLarge)

                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    inputGroup(title: "宝宝昵称") {
                        TextField("怎么称呼宝宝？", text: $model.nickname)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .padding(.horizontal, AppSpacing.large)
                            .frame(height: 50)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                                    .stroke(AppColors.mutedText.opacity(0.25), lineWidth: 1)
                            }
                    }

                    inputGroup(title: "出生日期") {
                        Button {
                            draftBirthDate = model.birthDate ?? Date()
                            showsBirthDatePicker = true
                        } label: {
                            HStack {
                                Text(model.birthDate.map(Self.displayDate) ?? "选择出生日期")
                                    .foregroundStyle(model.birthDate == nil ? AppColors.mutedText : AppColors.primaryText)
                                Spacer()
                                Image(systemName: "calendar")
                                    .foregroundStyle(AppColors.accent)
                            }
                            .padding(.horizontal, AppSpacing.large)
                            .frame(height: 50)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                                    .stroke(AppColors.mutedText.opacity(0.25), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        HStack {
                            Text("生长参考分组")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("用于匹配参考带")
                                .font(.caption)
                                .foregroundStyle(AppColors.mutedText)
                        }

                        HStack(spacing: AppSpacing.xSmall) {
                            growthOption(.female, title: "女童")
                            growthOption(.male, title: "男童")
                            growthOption(.unspecified, title: "暂不选择")
                        }
                        .padding(AppSpacing.xSmall)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                    }

                    Label(
                        "生长参考只用于显示国家标准参考带，不代替医生判断，也不会给宝宝贴‘正常/异常’标签。",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(AppSpacing.medium)
                    .background(AppColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                }
                .padding(.top, AppSpacing.xLarge)
            }
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .background(AppColors.surface)
        .safeAreaInset(edge: .bottom) {
            StickyPrimaryAction {
                PrimaryButton(
                    title: "下一步：选择记录模块",
                    isEnabled: model.canContinueFromProfile
                ) {
                    model.moveForward()
                }
                .accessibilityIdentifier("onboarding.profile.continue")
            }
        }
        .sheet(isPresented: $showsBirthDatePicker) {
            NavigationStack {
                DatePicker(
                    "出生日期",
                    selection: $draftBirthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("选择出生日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsBirthDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            model.birthDate = draftBirthDate
                            showsBirthDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .accessibilityIdentifier("onboarding.profile")
    }

    private var avatar: some View {
        VStack(spacing: AppSpacing.small) {
            Text(String(model.normalizedNickname.first ?? "宝"))
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(Color(red: 0.45, green: 0.37, blue: 0.33))
                .frame(width: 92, height: 92)
                .background(AppColors.peach.opacity(0.65))
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 5) }
                .shadow(color: AppColors.primaryText.opacity(0.08), radius: 16, y: 8)

            Text("头像可稍后添加")
                .font(.caption)
                .foregroundStyle(AppColors.mutedText)
        }
    }

    private func inputGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
            content()
        }
    }

    private func growthOption(
        _ group: GrowthReferenceGroup,
        title: String
    ) -> some View {
        let isSelected = model.growthReferenceGroup == group
        return Button(title) {
            model.growthReferenceGroup = group
        }
        .font(.caption.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? AppColors.primaryText : AppColors.mutedText)
        .frame(maxWidth: .infinity)
        .frame(height: 39)
        .background(isSelected ? .white : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: isSelected ? AppColors.primaryText.opacity(0.07) : .clear, radius: 6, y: 3)
    }

    private static func displayDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_Hans_CN")))
    }
}
