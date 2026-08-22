import Domain
import SwiftUI

enum AppTab: Hashable {
    case today
    case growth
    case record
    case moments
    case settings
}

@MainActor
struct MainTabView: View {
    let snapshot: OnboardingSnapshot
    @Bindable var router: AppRouter
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $router.path) {
                TodayView(
                    snapshot: snapshot,
                    onAddRecord: { router.navigate(to: .newRecord) },
                    onOpenHistory: { router.navigate(to: .history) },
                    onOpenSettings: { selectedTab = .settings }
                )
                .navigationDestination(for: AppRoute.self, destination: destination)
            }
            .tabItem { Label("今日", systemImage: "house") }
            .tag(AppTab.today)

            NavigationStack {
                tabPlaceholder(
                    symbol: "chart.xyaxis.line",
                    title: "成长",
                    message: "生长趋势会在 T4 接入真实测量与参考带。"
                )
            }
            .tabItem { Label("成长", systemImage: "chart.xyaxis.line") }
            .tag(AppTab.growth)

            NavigationStack {
                tabPlaceholder(
                    symbol: "plus.circle.fill",
                    title: "记录",
                    message: "T2 会在这里提供亲喂、吸奶、奶瓶、尿布和睡眠的全局入口。"
                )
            }
            .tabItem { Label("记录", systemImage: "plus.circle.fill") }
            .tag(AppTab.record)

            NavigationStack {
                tabPlaceholder(
                    symbol: "photo",
                    title: "相册",
                    message: "成长时光会在 T4 接入受保护的本地媒体流程。"
                )
            }
            .tabItem { Label("相册", systemImage: "photo") }
            .tag(AppTab.moments)

            NavigationStack {
                tabPlaceholder(
                    symbol: "person",
                    title: "我的",
                    message: "同意、导出、删除和本地数据控制将在后续阶段逐项接入。"
                )
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(AppTab.settings)
        }
        .tint(AppColors.accent)
        .toolbarBackground(AppColors.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .accessibilityIdentifier("main.tabs")
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .newRecord:
            tabPlaceholder(
                symbol: "plus.circle",
                title: "添加记录",
                message: "记录表单属于 T2；当前 T1 只交付真实建档与首页空态。"
            )
        case .history:
            tabPlaceholder(
                symbol: "clock.arrow.circlepath",
                title: "历史记录",
                message: "保存第一条照护记录后，历史页会接入统一时间线查询。"
            )
        case .settings:
            tabPlaceholder(
                symbol: "gearshape",
                title: "设置",
                message: "本地数据控制与模块排序会在对应阶段继续实现。"
            )
        }
    }

    private func tabPlaceholder(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 64, height: 64)
                .background(AppColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            Text(title)
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.primaryText)
            Text(message)
                .font(.body)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
