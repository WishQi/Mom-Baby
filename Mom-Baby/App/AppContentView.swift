import SwiftUI

@MainActor
struct AppContentView: View {
    let environment: AppEnvironment

    var body: some View {
        switch environment.experienceState {
        case .loading:
            VStack(spacing: AppSpacing.large) {
                ProgressView()
                    .controlSize(.large)
                Text("正在打开本地资料")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.primaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
            .accessibilityIdentifier("experience.loading")

        case .onboarding:
            OnboardingFlowView { request in
                try await environment.completeOnboarding(request)
            }

        case .ready(let snapshot):
            MainTabView(snapshot: snapshot, router: environment.router)
        }
    }
}
