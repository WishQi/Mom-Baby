import Domain
import SwiftUI

@MainActor
extension HomeModule {
    static let onboardingChoices: [HomeModule] = [
        .nursing,
        .pumping,
        .bottle,
        .diaper,
        .sleep,
    ]

    static let defaultHomeModules: [HomeModule] = [
        .nursing,
        .bottle,
        .diaper,
        .sleep,
    ]

    var displayName: String {
        switch self {
        case .nursing: "亲喂"
        case .pumping: "吸奶"
        case .bottle: "奶瓶"
        case .diaper: "尿布"
        case .sleep: "睡眠"
        case .growth: "成长"
        case .moments: "成长时光"
        case .supplies: "用品"
        }
    }

    var supportingText: String {
        switch self {
        case .nursing: "左右侧计时与补录"
        case .pumping: "分侧计时与奶量"
        case .bottle: "母乳、配方奶与用量"
        case .diaper: "小便、大便与混合"
        case .sleep: "计时与手工补录"
        case .growth: "身长与体重趋势"
        case .moments: "私密照片与月龄"
        case .supplies: "奶粉与奶瓶档案"
        }
    }

    var systemImage: String {
        switch self {
        case .nursing: "timer"
        case .pumping: "drop"
        case .bottle: "waterbottle"
        case .diaper: "shield.lefthalf.filled"
        case .sleep: "moon.stars"
        case .growth: "chart.xyaxis.line"
        case .moments: "photo"
        case .supplies: "shippingbox"
        }
    }

    var softColor: Color {
        switch self {
        case .nursing, .growth:
            AppColors.accentSoft
        case .pumping, .bottle, .moments:
            AppColors.peach
        case .diaper, .supplies:
            AppColors.gold
        case .sleep:
            AppColors.blue
        }
    }
}
