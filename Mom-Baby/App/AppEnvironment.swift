import Domain
import Observation
import Persistence

enum AppBootstrapState: Equatable, Sendable {
    case waitingForProtectedData
    case locatingVault
    case validatingHeader
    case preparingMigration
    case migratingSchema
    case migratingFiles
    case validatingResult
    case ready
    case protectionBlocked
    case newerSchema(found: Int, supported: Int)
    case recoveryRequired
    case readOnlyExport

    var beginsAutomatically: Bool {
        switch self {
        case .waitingForProtectedData,
             .locatingVault,
             .validatingHeader,
             .preparingMigration,
             .migratingSchema,
             .migratingFiles,
             .validatingResult:
            true
        case .ready,
             .protectionBlocked,
             .newerSchema,
             .recoveryRequired,
             .readOnlyExport:
            false
        }
    }

    var allowsRetry: Bool {
        switch self {
        case .waitingForProtectedData, .protectionBlocked, .recoveryRequired:
            true
        case .locatingVault,
             .validatingHeader,
             .preparingMigration,
             .migratingSchema,
             .migratingFiles,
             .validatingResult,
             .ready,
             .newerSchema,
             .readOnlyExport:
            false
        }
    }
}

enum AppExperienceState: Equatable, Sendable {
    case loading
    case onboarding
    case ready(OnboardingSnapshot)
}

@MainActor
@Observable
final class AppEnvironment {
    private enum BootstrapCommand: Sendable {
        case retry(protectedDataEpoch: UInt64)
    }

    let router: AppRouter

    private(set) var bootstrapState: AppBootstrapState
    private(set) var experienceState: AppExperienceState

    private let bootstrapClient: AppBootstrapClient
    private let bootstrapCommands: AsyncStream<BootstrapCommand>
    private let bootstrapCommandContinuation: AsyncStream<BootstrapCommand>.Continuation

    private var attemptGeneration: UInt64 = 0
    private var protectedDataEpoch: UInt64 = 0
    private var protectedDataIsAvailable: Bool
    private var protectedDataRevocationIsPending = false
    private var preparationLoopGeneration: UInt64 = 0
    private var preparationTask: Task<Void, Never>?
    private var retryIsQueued = false
    private var retryIsBlocked = false
    private var protectedDataSuspensionTask: Task<DatabaseCloseOutcome, Never>?
    private var protectedDataResumeTask: Task<Void, Never>?

    init(
        router: AppRouter,
        bootstrapClient: AppBootstrapClient,
        bootstrapState: AppBootstrapState,
        experienceState: AppExperienceState = .loading
    ) {
        let commandChannel = AsyncStream<BootstrapCommand>.makeStream()

        self.router = router
        self.bootstrapClient = bootstrapClient
        self.bootstrapState = bootstrapState
        self.experienceState = experienceState
        protectedDataIsAvailable = bootstrapClient.isProtectedDataAvailable()
        bootstrapCommands = commandChannel.stream
        bootstrapCommandContinuation = commandChannel.continuation
    }

    isolated deinit {
        preparationTask?.cancel()
        protectedDataSuspensionTask?.cancel()
        protectedDataResumeTask?.cancel()
        bootstrapCommandContinuation.finish()
    }

    static func live() -> AppEnvironment {
        let bootstrapClient = AppBootstrapClient.live()
        let initialState: AppBootstrapState = bootstrapClient.isProtectedDataAvailable()
            ? .locatingVault
            : .waitingForProtectedData

        return AppEnvironment(
            router: AppRouter(),
            bootstrapClient: bootstrapClient,
            bootstrapState: initialState
        )
    }

    static func preview(
        bootstrapState: AppBootstrapState = .ready,
        experienceState: AppExperienceState = .onboarding
    ) -> AppEnvironment {
        AppEnvironment(
            router: AppRouter(),
            bootstrapClient: .fake(
                outcome: .recoveryRequired(.closed)
            ),
            bootstrapState: bootstrapState,
            experienceState: experienceState
        )
    }

    /// Starts the environment-owned bootstrap consumer if it is not already running.
    ///
    /// The caller does not own the consumer's lifetime. In particular, SwiftUI may
    /// cancel a view `.task` as scenes come and go without cancelling bootstrap or
    /// permanently removing the only retry consumer.
    func prepareForUse() {
        guard preparationTask == nil else { return }

        preparationLoopGeneration &+= 1
        let loopGeneration = preparationLoopGeneration
        let commands = bootstrapCommands

        preparationTask = Task { [weak self] in
            if let self {
                self.refreshProtectedDataAvailabilityForColdStart()
                // Initial startup shares the same serialized command path as
                // retries and protected-data recovery. This keeps every demand
                // in a protection epoch single-flight.
                if self.bootstrapState.beginsAutomatically {
                    self.enqueueBootstrapAttempt()
                }
            }

            for await command in commands {
                guard !Task.isCancelled else { break }
                guard let self else { break }

                switch command {
                case .retry(let commandEpoch):
                    guard commandEpoch == self.protectedDataEpoch else { continue }
                    await self.performBootstrapAttempt()
                    if commandEpoch == self.protectedDataEpoch {
                        self.retryIsQueued = false
                    }
                }
            }

            self?.preparationLoopDidFinish(loopGeneration)
        }
    }

    func retryBootstrap() {
        guard canRetryBootstrap else { return }
        enqueueBootstrapAttempt()
    }

    var canRetryBootstrap: Bool {
        bootstrapState.allowsRetry && !retryIsBlocked
    }

    func protectedDataWillBecomeUnavailable() {
        protectedDataEpoch &+= 1
        let epoch = protectedDataEpoch
        protectedDataRevocationIsPending = true
        protectedDataIsAvailable = false
        attemptGeneration &+= 1
        protectedDataResumeTask?.cancel()
        protectedDataResumeTask = nil
        // Any queued command belongs to an older protection epoch. It stays in
        // the stream but will be discarded by the epoch check above.
        retryIsQueued = false
        bootstrapState = .waitingForProtectedData
        experienceState = .loading
        router.returnToRoot()
        let priorSuspensionTask = protectedDataSuspensionTask
        protectedDataSuspensionTask = Task { [weak self, bootstrapClient] in
            if let priorSuspensionTask {
                _ = await priorSuspensionTask.value
            }
            let result = await bootstrapClient.suspendForProtectedData()
            guard let self, epoch == self.protectedDataEpoch else { return result }
            if self.suspensionSucceeded(result) {
                self.retryIsBlocked = false
            } else {
                self.recordProtectedDataSuspensionFailure()
            }
            return result
        }
    }

    func protectedDataDidBecomeAvailable() {
        protectedDataRevocationIsPending = false
        guard !protectedDataIsAvailable else { return }

        protectedDataIsAvailable = true
        let epoch = protectedDataEpoch
        let suspensionTask = protectedDataSuspensionTask
        protectedDataResumeTask = Task { [weak self] in
            let closeOutcome = await suspensionTask?.value ?? .alreadyClosed
            guard !Task.isCancelled,
                  let self,
                  epoch == self.protectedDataEpoch,
                  self.protectedDataIsAvailable else { return }
            guard self.suspensionSucceeded(closeOutcome) else {
                self.recordProtectedDataSuspensionFailure()
                return
            }

            self.protectedDataSuspensionTask = nil
            self.retryIsBlocked = false
            self.retryBootstrap()
        }
    }

    /// Reconciles UIKit state when the app becomes active. This also covers a
    /// cold launch where `isProtectedDataAvailable` changed after composition
    /// but before RootView subscribed to UIKit's availability notification.
    func applicationDidBecomeActive() {
        // App-active is only a cold-start reconciliation signal. Once a real
        // `willBecomeUnavailable` advanced the epoch, UIKit's availability flag
        // may remain true during its grace window and must not revive access.
        guard protectedDataEpoch == 0,
              !protectedDataRevocationIsPending,
              bootstrapClient.isProtectedDataAvailable() else { return }
        protectedDataDidBecomeAvailable()
    }

    private func performBootstrapAttempt() async {
        let expectedProtectedDataEpoch = protectedDataEpoch
        if let protectedDataSuspensionTask {
            let closeOutcome = await protectedDataSuspensionTask.value
            if expectedProtectedDataEpoch == protectedDataEpoch {
                self.protectedDataSuspensionTask = nil
            }
            guard suspensionSucceeded(closeOutcome) else {
                recordProtectedDataSuspensionFailure()
                return
            }
        }

        guard expectedProtectedDataEpoch == protectedDataEpoch else { return }

        attemptGeneration &+= 1
        let generation = attemptGeneration

        guard protectedDataIsAvailable,
              bootstrapClient.isProtectedDataAvailable() else {
            protectedDataIsAvailable = false
            bootstrapState = .waitingForProtectedData
            return
        }

        bootstrapState = .locatingVault
        let outcome = await bootstrapClient.bootstrap(true) { [weak self] phase in
            await self?.receive(phase, for: generation)
        }

        guard !Task.isCancelled,
              generation == attemptGeneration,
              expectedProtectedDataEpoch == protectedDataEpoch,
              protectedDataIsAvailable else { return }
        let nextBootstrapState = state(for: outcome)
        guard nextBootstrapState == .ready else {
            experienceState = .loading
            bootstrapState = nextBootstrapState
            return
        }

        do {
            let loadState = try await bootstrapClient.loadOnboarding()
            guard !Task.isCancelled,
                  generation == attemptGeneration,
                  expectedProtectedDataEpoch == protectedDataEpoch,
                  protectedDataIsAvailable else { return }
            switch loadState {
            case .incomplete:
                experienceState = .onboarding
            case .complete(let snapshot):
                experienceState = .ready(snapshot)
            }
            bootstrapState = .ready
        } catch {
            experienceState = .loading
            bootstrapState = .recoveryRequired
        }
    }

    func completeOnboarding(
        _ request: CompleteOnboardingRequest
    ) async throws -> OnboardingSnapshot {
        guard bootstrapState == .ready,
              protectedDataIsAvailable,
              bootstrapClient.isProtectedDataAvailable() else {
            throw AppExperienceError.unavailable
        }

        let expectedEpoch = protectedDataEpoch
        let snapshot = try await bootstrapClient.completeOnboarding(request)
        guard expectedEpoch == protectedDataEpoch,
              protectedDataIsAvailable,
              bootstrapState == .ready else {
            throw AppExperienceError.unavailable
        }

        router.returnToRoot()
        experienceState = .ready(snapshot)
        return snapshot
    }

    private func refreshProtectedDataAvailabilityForColdStart() {
        guard !protectedDataRevocationIsPending,
              !protectedDataIsAvailable,
              bootstrapClient.isProtectedDataAvailable() else { return }
        protectedDataIsAvailable = true
    }

    private func enqueueBootstrapAttempt() {
        guard !retryIsQueued else { return }

        retryIsQueued = true
        bootstrapCommandContinuation.yield(
            .retry(protectedDataEpoch: protectedDataEpoch)
        )
    }

    private func preparationLoopDidFinish(_ generation: UInt64) {
        guard generation == preparationLoopGeneration else { return }
        preparationTask = nil
    }

    private func recordProtectedDataSuspensionFailure() {
        retryIsBlocked = true
        retryIsQueued = false
        experienceState = .loading
        router.returnToRoot()
        bootstrapState = .recoveryRequired
    }

    private func suspensionSucceeded(_ outcome: DatabaseCloseOutcome) -> Bool {
        switch outcome {
        case .closed, .alreadyClosed:
            true
        case .failed:
            false
        @unknown default:
            false
        }
    }

    private func receive(
        _ phase: DatabaseBootstrapPhase,
        for generation: UInt64
    ) {
        guard !Task.isCancelled, generation == attemptGeneration else { return }
        bootstrapState = state(for: phase)
    }

    private func state(for phase: DatabaseBootstrapPhase) -> AppBootstrapState {
        switch phase {
        case .waitingForProtectedData:
            .waitingForProtectedData
        case .locatingVault:
            .locatingVault
        case .validatingHeader:
            .validatingHeader
        case .preparingMigration:
            .preparingMigration
        case .migratingSchema:
            .migratingSchema
        case .migratingFiles:
            .migratingFiles
        case .validatingResult:
            .validatingResult
        case .ready:
            .ready
        @unknown default:
            .recoveryRequired
        }
    }

    private func state(for outcome: DatabaseBootstrapOutcome) -> AppBootstrapState {
        switch outcome {
        case .ready:
            .ready
        case .waitingForProtectedData:
            .waitingForProtectedData
        case .protectionBlocked:
            .protectionBlocked
        case .newerSchema(let found, let supported):
            .newerSchema(found: found, supported: supported)
        case .recoveryRequired:
            .recoveryRequired
        case .readOnlyExport:
            .readOnlyExport
        @unknown default:
            .recoveryRequired
        }
    }
}

enum AppExperienceError: Error {
    case unavailable
}
