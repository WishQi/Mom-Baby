import Domain
import Foundation
import Persistence
import UIKit

struct AppBootstrapClient: Sendable {
    typealias ProgressHandler = @Sendable (DatabaseBootstrapPhase) async -> Void
    typealias BootstrapOperation = @Sendable (
        _ protectedDataAvailable: Bool,
        _ progress: @escaping ProgressHandler
    ) async -> DatabaseBootstrapOutcome
    typealias LoadOnboardingOperation = @Sendable () async throws -> OnboardingLoadState
    typealias CompleteOnboardingOperation = @Sendable (
        CompleteOnboardingRequest
    ) async throws -> OnboardingSnapshot

    let isProtectedDataAvailable: @MainActor @Sendable () -> Bool
    let bootstrap: BootstrapOperation
    let suspendForProtectedData: @Sendable () async -> DatabaseCloseOutcome
    let loadOnboarding: LoadOnboardingOperation
    let completeOnboarding: CompleteOnboardingOperation

    init(
        isProtectedDataAvailable: @escaping @MainActor @Sendable () -> Bool,
        bootstrap: @escaping BootstrapOperation,
        suspendForProtectedData: @escaping @Sendable () async -> DatabaseCloseOutcome,
        loadOnboarding: @escaping LoadOnboardingOperation = { .incomplete },
        completeOnboarding: @escaping CompleteOnboardingOperation = { _ in
            throw AppBootstrapClientError.databaseUnavailable
        }
    ) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.bootstrap = bootstrap
        self.suspendForProtectedData = suspendForProtectedData
        self.loadOnboarding = loadOnboarding
        self.completeOnboarding = completeOnboarding
    }

    @MainActor
    static func live() -> AppBootstrapClient {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let service = LiveDatabaseBootstrapService(
            applicationSupportDirectory: applicationSupportDirectory
        )

        return AppBootstrapClient(
            isProtectedDataAvailable: {
                UIApplication.shared.isProtectedDataAvailable
            },
            bootstrap: { protectedDataAvailable, progress in
                await service.bootstrap(
                    protectedDataAvailable: protectedDataAvailable,
                    progress: progress
                )
            },
            suspendForProtectedData: {
                await service.suspendForProtectedData()
            },
            loadOnboarding: {
                try await service.loadOnboarding()
            },
            completeOnboarding: { request in
                try await service.completeOnboarding(request)
            }
        )
    }

    /// A deterministic seam for previews and future state-mapping tests.
    @MainActor
    static func fake(
        protectedDataAvailable: Bool = true,
        phases: [DatabaseBootstrapPhase] = [],
        outcome: DatabaseBootstrapOutcome,
        suspendOutcome: DatabaseCloseOutcome = .alreadyClosed
    ) -> AppBootstrapClient {
        AppBootstrapClient(
            isProtectedDataAvailable: { protectedDataAvailable },
            bootstrap: { _, progress in
                for phase in phases {
                    await progress(phase)
                }
                return outcome
            },
            suspendForProtectedData: { suspendOutcome },
            loadOnboarding: { .incomplete }
        )
    }
}

private actor LiveDatabaseBootstrapService {
    private let applicationSupportDirectory: URL?
    private var coordinator: DatabaseBootstrapCoordinator?

    init(applicationSupportDirectory: URL?) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    func bootstrap(
        protectedDataAvailable: Bool,
        progress: @escaping DatabaseBootstrapCoordinator.ProgressHandler
    ) async -> DatabaseBootstrapOutcome {
        guard let applicationSupportDirectory else {
            return .recoveryRequired(.invalidVault)
        }

        let activeCoordinator: DatabaseBootstrapCoordinator
        if let coordinator {
            activeCoordinator = coordinator
        } else {
            activeCoordinator = .live(
                applicationSupportDirectory: applicationSupportDirectory
            )
            coordinator = activeCoordinator
        }

        return await activeCoordinator.bootstrap(
            protectedDataAvailable: protectedDataAvailable,
            progress: progress
        )
    }

    func suspendForProtectedData() async -> DatabaseCloseOutcome {
        guard let coordinator else { return .alreadyClosed }
        return await coordinator.suspendForProtectedData()
    }

    func loadOnboarding() async throws -> OnboardingLoadState {
        guard let coordinator else {
            throw AppBootstrapClientError.databaseUnavailable
        }
        return try await coordinator.loadOnboarding()
    }

    func completeOnboarding(
        _ request: CompleteOnboardingRequest
    ) async throws -> OnboardingSnapshot {
        guard let coordinator else {
            throw AppBootstrapClientError.databaseUnavailable
        }
        return try await coordinator.completeOnboarding(request)
    }
}

enum AppBootstrapClientError: Error {
    case databaseUnavailable
}
