import Domain
import SwiftUI

@MainActor
struct TodayView: View {
    let snapshot: OnboardingSnapshot
    let onAddRecord: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void

    @State private var selectedDate = Date()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                profileHeader
                dateStrip.padding(.top, AppSpacing.large)
                emptySummaryHero.padding(.top, AppSpacing.large)
                quickRecordSection.padding(.top, AppSpacing.section)
                emptyTimelineSection.padding(.top, AppSpacing.section)
            }
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .background(AppColors.surface)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("today.root")
    }

    private var profileHeader: some View {
        HStack(spacing: 11) {
            Text(avatarInitial)
                .font(.body)
                .foregroundStyle(Color(red: 0.45, green: 0.37, blue: 0.33))
                .frame(width: 46, height: 46)
                .background(AppColors.peach.opacity(0.72))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.headerDate)
                    .font(.caption2)
                    .foregroundStyle(AppColors.mutedText)
                Text("\(snapshot.baby.nickname) · \(ageText)")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: AppSpacing.xSmall)

            Button(action: onOpenHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("历史记录")

            Button(action: onOpenSettings) {
                Image(systemName: "checkmark.shield")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("本地保存")
        }
        .foregroundStyle(AppColors.primaryText)
    }

    private var dateStrip: some View {
        HStack(spacing: 4) {
            ForEach(Self.visibleDates, id: \.timeIntervalSinceReferenceDate) { date in
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "zh_Hans_CN"))))
                            .font(.caption2)
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? .white : AppColors.mutedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(isSelected ? AppColors.accent : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            }
        }
    }

    private var emptySummaryHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("距离上次喂养")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.80))
            Text("还没有记录")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.top, AppSpacing.small)

            HStack(spacing: AppSpacing.section) {
                summaryMetric(value: "0 分钟", label: "今日亲喂")
                summaryMetric(value: "0 ml", label: "今日奶瓶")
                summaryMetric(value: "0 次", label: "今日尿布")
            }
            .padding(.top, AppSpacing.large)
        }
        .padding(AppSpacing.section)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [AppColors.accent, Color(red: 0.47, green: 0.58, blue: 0.50)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
                    .frame(width: 146, height: 146)
                    .offset(x: 40, y: -58)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.hero, style: .continuous))
        .shadow(color: AppColors.accent.opacity(0.20), radius: 18, y: 13)
        .accessibilityElement(children: .combine)
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(minWidth: 76, alignment: .leading)
    }

    private var quickRecordSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("快速记录")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Button("全部", action: onAddRecord)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .buttonStyle(.plain)
            }

            HStack(spacing: AppSpacing.small) {
                ForEach(quickModules, id: \.rawValue) { module in
                    Button(action: onAddRecord) {
                        VStack(spacing: AppSpacing.small) {
                            Image(systemName: module.systemImage)
                                .font(.body)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 35, height: 35)
                                .background(module.softColor)
                                .clipShape(Circle())
                            Text(module.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.primaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 78)
                        .background(.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColors.mutedText.opacity(0.20), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyTimelineSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text(Calendar.current.isDateInToday(selectedDate) ? "今天" : "这一天")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Button("查看全部", action: onOpenHistory)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .buttonStyle(.plain)
            }

            VStack(spacing: AppSpacing.medium) {
                Image(systemName: "heart.text.clipboard")
                    .font(.title2)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("这一天还没有照护记录")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Text("从上面的快捷入口开始，保存后会在这里形成统一时间线。")
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .multilineTextAlignment(.center)
                Button(action: onAddRecord) {
                    Label("添加第一条记录", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AppMetrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(AppSpacing.xLarge)
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        }
    }

    private var quickModules: [HomeModule] {
        let configured = snapshot.homeModules.filter { HomeModule.onboardingChoices.contains($0) }
        if !configured.isEmpty {
            return Array(configured.prefix(4))
        }
        return Array(snapshot.enabledModules.filter { HomeModule.onboardingChoices.contains($0) }.prefix(4))
    }

    private var avatarInitial: String {
        snapshot.baby.nickname.first.map(String.init) ?? "宝"
    }

    private var ageText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: snapshot.baby.homeTimeZone) ?? .current
        let parts = snapshot.baby.birthLocalDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let birth = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return "月龄待确认"
        }
        let today = calendar.startOfDay(for: Date())
        let age = calendar.dateComponents([.year, .month, .day], from: birth, to: today)
        if let year = age.year, year > 0 {
            return "\(year)岁\(age.month ?? 0)个月"
        }
        if let month = age.month, month > 0 {
            return "\(month)个月\(age.day ?? 0)天"
        }
        return "\(max(0, age.day ?? 0))天"
    }

    private static var headerDate: String {
        Date().formatted(
            .dateTime.year().month().day().weekday(.wide)
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }

    private static var visibleDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-4...2).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }
}

#Preview {
    NavigationStack {
        TodayView(
            snapshot: OnboardingSnapshot(
                localVaultID: "vault",
                localActorID: "actor",
                baby: BabyProfileSnapshot(
                    id: "baby",
                    nickname: "小满",
                    birthLocalDate: "2026-06-09",
                    growthReferenceGroup: .unspecified,
                    homeTimeZone: "Asia/Shanghai"
                ),
                lactatingProfileID: nil,
                enabledModules: [.nursing, .bottle, .diaper, .sleep, .growth, .moments],
                homeModules: [.nursing, .bottle, .diaper, .sleep]
            ),
            onAddRecord: {},
            onOpenHistory: {},
            onOpenSettings: {}
        )
    }
}
