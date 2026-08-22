import Combine
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    let environment: AppEnvironment

    var body: some View {
        ZStack {
            switch environment.bootstrapState {
            case .waitingForProtectedData:
                BootstrapIssueView(
                    symbol: "lock.fill",
                    symbolColor: AppColors.secondaryText,
                    title: "bootstrap.waiting_for_protected_data.title",
                    message: "bootstrap.waiting_for_protected_data.message",
                    accessibilityIdentifier: "bootstrap.waiting_for_protected_data",
                    actionTitle: "bootstrap.action.retry",
                    action: environment.retryBootstrap
                )
            case .locatingVault:
                BootstrapProgressView(
                    title: "bootstrap.locating_vault.title",
                    message: "bootstrap.locating_vault.message",
                    accessibilityIdentifier: "bootstrap.locating_vault"
                )
            case .validatingHeader:
                BootstrapProgressView(
                    title: "bootstrap.validating_header.title",
                    message: "bootstrap.validating_header.message",
                    accessibilityIdentifier: "bootstrap.validating_header"
                )
            case .preparingMigration:
                BootstrapProgressView(
                    title: "bootstrap.preparing_migration.title",
                    message: "bootstrap.preparing_migration.message",
                    accessibilityIdentifier: "bootstrap.preparing_migration"
                )
            case .migratingSchema:
                BootstrapProgressView(
                    title: "bootstrap.migrating_schema.title",
                    message: "bootstrap.migrating_schema.message",
                    accessibilityIdentifier: "bootstrap.migrating_schema"
                )
            case .migratingFiles:
                BootstrapProgressView(
                    title: "bootstrap.migrating_files.title",
                    message: "bootstrap.migrating_files.message",
                    accessibilityIdentifier: "bootstrap.migrating_files"
                )
            case .validatingResult:
                BootstrapProgressView(
                    title: "bootstrap.validating_result.title",
                    message: "bootstrap.validating_result.message",
                    accessibilityIdentifier: "bootstrap.validating_result"
                )
            case .ready:
                AppContentView(environment: environment)
            case .protectionBlocked:
                BootstrapIssueView(
                    symbol: "lock.trianglebadge.exclamationmark",
                    symbolColor: AppColors.warning,
                    title: "bootstrap.protection_blocked.title",
                    message: "bootstrap.protection_blocked.message",
                    accessibilityIdentifier: "bootstrap.protection_blocked",
                    actionTitle: "bootstrap.action.retry",
                    action: environment.retryBootstrap
                )
            case .newerSchema(_, _):
                BootstrapIssueView(
                    symbol: "arrow.down.app.fill",
                    symbolColor: AppColors.warning,
                    title: "bootstrap.newer_schema.title",
                    message: "bootstrap.newer_schema.message",
                    accessibilityIdentifier: "bootstrap.newer_schema"
                )
            case .recoveryRequired:
                BootstrapIssueView(
                    symbol: "externaldrive.badge.exclamationmark",
                    symbolColor: AppColors.warning,
                    title: "bootstrap.recovery.title",
                    message: "bootstrap.recovery.message",
                    accessibilityIdentifier: "bootstrap.recovery_required",
                    actionTitle: "bootstrap.action.retry",
                    action: environment.retryBootstrap,
                    showsAction: environment.canRetryBootstrap
                )
            case .readOnlyExport:
                BootstrapIssueView(
                    symbol: "archivebox.fill",
                    symbolColor: AppColors.warning,
                    title: "bootstrap.read_only_export.title",
                    message: "bootstrap.read_only_export.message",
                    accessibilityIdentifier: "bootstrap.read_only_export"
                )
            }

            if scenePhase != .active {
                PrivacyShieldView()
                    .zIndex(1)
            }
        }
        .task {
            environment.prepareForUse()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.protectedDataWillBecomeUnavailableNotification
            )
        ) { _ in
            environment.protectedDataWillBecomeUnavailable()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.protectedDataDidBecomeAvailableNotification
            )
        ) { _ in
            environment.protectedDataDidBecomeAvailable()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active else { return }
            environment.applicationDidBecomeActive()
        }
        .accessibilityIdentifier("app.root")
    }
}

@MainActor
private struct PrivacyShieldView: View {
    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 62, height: 62)
                .background(AppColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            Text("Mom-Baby")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mom-Baby 已隐藏照护资料")
        .accessibilityIdentifier("privacy.shield")
    }
}

@MainActor
private struct BootstrapProgressView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let accessibilityIdentifier: String

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(AppTypography.headline)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

@MainActor
private struct BootstrapIssueView: View {
    let symbol: String
    let symbolColor: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let accessibilityIdentifier: String
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    var showsAction = true

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            Text(title)
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
            if showsAction, let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minHeight: AppMetrics.minimumTapTarget)
            }
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview {
    RootView(environment: AppEnvironment.preview())
}
