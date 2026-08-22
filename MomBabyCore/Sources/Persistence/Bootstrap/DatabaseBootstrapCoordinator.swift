import Foundation
import GRDB
import Domain

/// Coordinates vault discovery, schema migration, validation, and connection
/// lifecycle without exposing GRDB to the App target.
public actor DatabaseBootstrapCoordinator {
    public typealias ProgressHandler = @Sendable (DatabaseBootstrapPhase) async -> Void

    enum Storage: Sendable {
        case live(applicationSupportDirectory: URL)
        case inMemory
        case temporary(directory: URL)
    }

    private let storage: Storage
    private let dependencies: PersistenceDependencies
    private let makeMigrator: @Sendable (Int64) throws -> DatabaseMigrator
    private let closeOwnerOperation: @Sendable (DatabaseOwner) async -> DatabaseCloseOutcome
    private let suspensionStarted: @Sendable () -> Void

    private var owner: DatabaseOwner?
    private var readyReport: DatabaseValidationReport?
    private var readyStorage: ResolvedStorage?
    private var ephemeralSecurityMaterial: OnboardingSecurityMaterial?
    private var lifecycleGeneration: UInt64 = 0
    private var isBootstrapping = false
    private var isSuspending = false
    private var suspensionFailed = false
    private var isClosed = false
    private var bootstrapStopWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionWaiters: [CheckedContinuation<DatabaseCloseOutcome, Never>] = []

    init(
        storage: Storage,
        dependencies: PersistenceDependencies,
        makeMigrator: @escaping @Sendable (Int64) throws -> DatabaseMigrator = {
            try AppDatabaseMigrator(installedAtMilliseconds: $0).migrator
        },
        closeOwner: @escaping @Sendable (DatabaseOwner) async -> DatabaseCloseOutcome = {
            await $0.close()
        },
        suspensionStarted: @escaping @Sendable () -> Void = {}
    ) {
        self.storage = storage
        self.dependencies = dependencies
        self.makeMigrator = makeMigrator
        closeOwnerOperation = closeOwner
        self.suspensionStarted = suspensionStarted
    }

    /// Creates the live, on-disk bootstrap coordinator.
    public nonisolated static func live(
        applicationSupportDirectory: URL,
        dependencies: PersistenceDependencies = .system()
    ) -> DatabaseBootstrapCoordinator {
        DatabaseBootstrapCoordinator(
            storage: .live(applicationSupportDirectory: applicationSupportDirectory),
            dependencies: dependencies
        )
    }

    /// Creates one coordinator backed by one shared in-memory DatabaseQueue.
    public nonisolated static func inMemory(
        dependencies: PersistenceDependencies = .system()
    ) -> DatabaseBootstrapCoordinator {
        DatabaseBootstrapCoordinator(
            storage: .inMemory,
            dependencies: dependencies
        )
    }

    /// Creates a production-like DatabasePool in a caller-owned temporary root.
    public nonisolated static func temporary(
        directory: URL,
        dependencies: PersistenceDependencies = .system()
    ) -> DatabaseBootstrapCoordinator {
        DatabaseBootstrapCoordinator(
            storage: .temporary(directory: directory),
            dependencies: dependencies
        )
    }

    /// Runs one idempotent bootstrap attempt.
    ///
    /// Every suspension revokes the current generation. Checks after each
    /// suspension point prevent a revoked attempt from creating an owner,
    /// performing its next SQLite operation, or publishing a ready result.
    public func bootstrap(
        protectedDataAvailable: Bool = true,
        progress: @escaping ProgressHandler = { _ in }
    ) async -> DatabaseBootstrapOutcome {
        guard !isClosed else {
            return .recoveryRequired(.closed)
        }
        guard protectedDataAvailable else {
            let closeOutcome = await suspendForProtectedData()
            await progress(.waitingForProtectedData)
            return closeOutcome == .failed
                ? .recoveryRequired(.closeFailed)
                : .waitingForProtectedData
        }
        guard !isSuspending else {
            return .waitingForProtectedData
        }
        guard !suspensionFailed else {
            return .recoveryRequired(.closeFailed)
        }
        guard !isBootstrapping else {
            return .recoveryRequired(.alreadyInProgress)
        }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        isBootstrapping = true
        defer { finishBootstrapAttempt() }

        if let readyReport {
            guard await emit(.ready, for: generation, to: progress) else {
                return interruptionOutcome()
            }
            return .ready(readyReport)
        }

        guard await emit(.locatingVault, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        let resolvedStorage: ResolvedStorage
        do {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            resolvedStorage = try resolveStorage()
        } catch VaultLocationError.protectionFailed {
            return .protectionBlocked
        } catch VaultLocationError.unavailablePointer {
            return .recoveryRequired(.vaultUnavailable)
        } catch {
            return .recoveryRequired(.invalidVault)
        }

        guard await emit(.validatingHeader, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        if case .disk(let location, let allowsEmptyDatabase) = resolvedStorage {
            do {
                guard isAttemptActive(generation) else {
                    return interruptionOutcome()
                }
                switch try DatabaseCompatibility.inspect(databaseURL: location.databaseURL) {
                case .empty where allowsEmptyDatabase:
                    break
                case .empty:
                    return .recoveryRequired(.invalidVault)
                case .current:
                    break
                case .newer(let version):
                    return .newerSchema(
                        found: version,
                        supported: SchemaContract.currentVersion
                    )
                }
            } catch {
                return .recoveryRequired(.validationFailed)
            }
        }

        guard await emit(.preparingMigration, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        let databaseOwner: DatabaseOwner
        do {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            if let owner {
                databaseOwner = owner
            } else {
                databaseOwner = try makeOwner(for: resolvedStorage)
                owner = databaseOwner
            }
        } catch {
            return .recoveryRequired(.openFailed)
        }

        let installedAtMilliseconds = max(
            1,
            Int64(dependencies.clock.now.timeIntervalSince1970 * 1_000)
        )
        guard await emit(.migratingSchema, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        do {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            let migrator = try makeMigrator(installedAtMilliseconds)
            try await databaseOwner.migrate(migrator)
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
        } catch {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            dependencies.logger.log(
                PrivacyLogEvent(
                    level: .error,
                    category: .persistence,
                    message: "database_migration_failed"
                )
            )
            return await closeOwnerAfterFailure(
                .recoveryRequired(.migrationFailed),
                generation: generation
            )
        }

        // v1 has no file-layout migration, but the explicit phase keeps the
        // bootstrap protocol stable for the first migration that does.
        guard await emit(.migratingFiles, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        if case .disk(let location, _) = resolvedStorage {
            do {
                guard isAttemptActive(generation) else {
                    return interruptionOutcome()
                }
                try VaultLocator.protectDatabaseArtifacts(
                    databaseURL: location.databaseURL
                )
            } catch {
                return await closeOwnerAfterFailure(
                    .protectionBlocked,
                    generation: generation
                )
            }
        }

        guard await emit(.validatingResult, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        let report: DatabaseValidationReport
        do {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            report = try await DatabaseValidator.validate(databaseOwner)
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
        } catch {
            guard isAttemptActive(generation) else {
                return interruptionOutcome()
            }
            dependencies.logger.log(
                PrivacyLogEvent(
                    level: .error,
                    category: .persistence,
                    message: "database_validation_failed"
                )
            )
            return await closeOwnerAfterFailure(
                .recoveryRequired(.validationFailed),
                generation: generation
            )
        }

        if case .disk(let location, _) = resolvedStorage {
            do {
                guard isAttemptActive(generation) else {
                    return interruptionOutcome()
                }
                try VaultLocator.activateAfterValidation(location)
            } catch VaultLocationError.protectionFailed {
                return await closeOwnerAfterFailure(
                    .protectionBlocked,
                    generation: generation
                )
            } catch {
                return await closeOwnerAfterFailure(
                    .recoveryRequired(.invalidVault),
                    generation: generation
                )
            }
        }

        guard isAttemptActive(generation) else {
            return interruptionOutcome()
        }
        readyReport = report
        readyStorage = resolvedStorage
        guard await emit(.ready, for: generation, to: progress) else {
            return interruptionOutcome()
        }
        return .ready(report)
    }

    /// Revokes an in-flight bootstrap and closes the single database owner.
    /// Concurrent callers share the same suspension result.
    public func suspendForProtectedData() async -> DatabaseCloseOutcome {
        if isSuspending {
            return await withCheckedContinuation { continuation in
                suspensionWaiters.append(continuation)
            }
        }

        isSuspending = true
        lifecycleGeneration &+= 1
        readyReport = nil
        readyStorage = nil
        suspensionStarted()

        let ownerAtRevocation = owner
        let closeOutcome: DatabaseCloseOutcome
        if let ownerAtRevocation {
            closeOutcome = await closeOwnerOperation(ownerAtRevocation)
            switch closeOutcome {
            case .closed, .alreadyClosed:
                if owner === ownerAtRevocation {
                    owner = nil
                }
                suspensionFailed = false
            case .failed:
                // The failed owner may still hold SQLite handles. Keep it and
                // reject all later bootstraps until a close retry succeeds.
                suspensionFailed = true
            }
        } else {
            closeOutcome = .alreadyClosed
            suspensionFailed = false
        }

        if isBootstrapping {
            await waitForBootstrapToStop()
        }
        finishSuspension(with: closeOutcome)
        return closeOutcome
    }

    /// Permanently closes this coordinator instance.
    public func close() async -> DatabaseCloseOutcome {
        isClosed = true
        return await suspendForProtectedData()
    }

    /// Loads the atomic onboarding aggregate without exposing GRDB or row
    /// types to the App target. Any partial aggregate or missing device-bound
    /// security material fails closed.
    public func loadOnboarding() async throws -> OnboardingLoadState {
        guard readyReport != nil,
              let owner,
              let readyStorage,
              !isSuspending,
              !isClosed else {
            throw OnboardingError.unavailable
        }
        let generation = lifecycleGeneration

        let hasState: Bool
        do {
            hasState = try await owner.read(OnboardingRepository.hasAnyState)
        } catch {
            throw OnboardingError.unavailable
        }
        guard isReadyOperationActive(generation, owner: owner) else {
            throw OnboardingError.unavailable
        }
        guard hasState else { return .incomplete }

        let security = try existingSecurityMaterial(for: readyStorage)
        guard let security else {
            throw OnboardingError.restoreReviewRequired
        }
        do {
            let state = try await owner.read { database in
                try OnboardingRepository.load(
                    database,
                    security: security
                )
            }
            guard isReadyOperationActive(generation, owner: owner) else {
                throw OnboardingError.unavailable
            }
            return state
        } catch let error as OnboardingError {
            throw error
        } catch {
            guard isReadyOperationActive(generation, owner: owner) else {
                throw OnboardingError.unavailable
            }
            throw OnboardingError.inconsistentState
        }
    }

    /// Atomically creates the vault identity, actor, installation, separate
    /// child/adult consent subjects, baby profile, and all module preferences.
    public func completeOnboarding(
        _ request: CompleteOnboardingRequest
    ) async throws -> OnboardingSnapshot {
        guard readyReport != nil,
              let owner,
              let readyStorage,
              !isSuspending,
              !isClosed else {
            throw OnboardingError.unavailable
        }
        let generation = lifecycleGeneration

        let now = dependencies.clock.now
        let validated = try OnboardingRequestValidator.validate(request, now: now)
        let hasState: Bool
        do {
            hasState = try await owner.read(OnboardingRepository.hasAnyState)
        } catch {
            throw OnboardingError.unavailable
        }
        guard isReadyOperationActive(generation, owner: owner) else {
            throw OnboardingError.unavailable
        }
        let security: OnboardingSecurityMaterial
        if hasState {
            guard let existing = try existingSecurityMaterial(for: readyStorage) else {
                throw OnboardingError.restoreReviewRequired
            }
            security = existing
        } else {
            security = try loadOrCreateSecurityMaterial(for: readyStorage)
        }

        let nowMilliseconds = max(1, Int64(now.timeIntervalSince1970 * 1_000))
        let uuid = dependencies.uuid
        do {
            let snapshot = try await owner.write { database in
                try OnboardingRepository.complete(
                    validated,
                    in: database,
                    nowMilliseconds: nowMilliseconds,
                    security: security,
                    uuid: uuid
                )
            }
            guard isReadyOperationActive(generation, owner: owner) else {
                throw OnboardingError.unavailable
            }
            return snapshot
        } catch let error as OnboardingError {
            throw error
        } catch {
            guard isReadyOperationActive(generation, owner: owner) else {
                throw OnboardingError.unavailable
            }
            throw OnboardingError.inconsistentState
        }
    }

    private enum ResolvedStorage: Sendable {
        case disk(location: VaultLocation, allowsEmptyDatabase: Bool)
        case inMemory
    }

    private func isReadyOperationActive(
        _ generation: UInt64,
        owner expectedOwner: DatabaseOwner
    ) -> Bool {
        lifecycleGeneration == generation &&
            owner === expectedOwner &&
            readyReport != nil &&
            readyStorage != nil &&
            !isSuspending &&
            !isClosed
    }

    private func existingSecurityMaterial(
        for storage: ResolvedStorage
    ) throws -> OnboardingSecurityMaterial? {
        do {
            switch storage {
            case .disk(let location, _):
                switch self.storage {
                case .live:
                    return try OnboardingSecurityStore.loadExistingLive(
                        location: location
                    )
                case .temporary:
                    return try OnboardingSecurityStore.loadExistingTemporary(
                        location: location
                    )
                case .inMemory:
                    throw OnboardingError.inconsistentState
                }
            case .inMemory:
                return ephemeralSecurityMaterial
            }
        } catch let error as OnboardingError {
            throw error
        } catch {
            throw OnboardingError.securityMaterialUnavailable
        }
    }

    private func loadOrCreateSecurityMaterial(
        for storage: ResolvedStorage
    ) throws -> OnboardingSecurityMaterial {
        do {
            switch storage {
            case .disk(let location, _):
                switch self.storage {
                case .live:
                    return try OnboardingSecurityStore.loadOrCreateLive(
                        location: location,
                        uuid: dependencies.uuid
                    )
                case .temporary:
                    return try OnboardingSecurityStore.loadOrCreateTemporary(
                        location: location,
                        uuid: dependencies.uuid
                    )
                case .inMemory:
                    throw OnboardingError.inconsistentState
                }
            case .inMemory:
                if let ephemeralSecurityMaterial {
                    return ephemeralSecurityMaterial
                }
                let material = try OnboardingSecurityStore.makeEphemeral(
                    uuid: dependencies.uuid
                )
                ephemeralSecurityMaterial = material
                return material
            }
        } catch let error as OnboardingError {
            throw error
        } catch {
            throw OnboardingError.securityMaterialUnavailable
        }
    }

    private func resolveStorage() throws -> ResolvedStorage {
        switch storage {
        case .live(let applicationSupportDirectory):
            let location = try VaultLocator.locateOrCreate(
                applicationSupportDirectory: applicationSupportDirectory,
                uuid: dependencies.uuid
            )
            return .disk(
                location: location,
                allowsEmptyDatabase: location.isProvisioning
            )
        case .temporary(let directory):
            return .disk(
                location: try VaultLocator.prepareTemporaryDirectory(directory),
                allowsEmptyDatabase: true
            )
        case .inMemory:
            return .inMemory
        }
    }

    private func makeOwner(for storage: ResolvedStorage) throws -> DatabaseOwner {
        switch storage {
        case .disk(let location, _):
            return try DatabaseOwnerFactory.production(at: location.databaseURL)
        case .inMemory:
            return try DatabaseOwnerFactory.inMemory()
        }
    }

    private func emit(
        _ phase: DatabaseBootstrapPhase,
        for generation: UInt64,
        to progress: ProgressHandler
    ) async -> Bool {
        guard isAttemptActive(generation) else { return false }
        await progress(phase)
        return isAttemptActive(generation)
    }

    private func isAttemptActive(_ generation: UInt64) -> Bool {
        lifecycleGeneration == generation && !isSuspending && !isClosed
    }

    private func interruptionOutcome() -> DatabaseBootstrapOutcome {
        if isClosed {
            return .recoveryRequired(.closed)
        }
        if suspensionFailed {
            return .recoveryRequired(.closeFailed)
        }
        return .waitingForProtectedData
    }

    private func closeOwnerAfterFailure(
        _ intendedOutcome: DatabaseBootstrapOutcome,
        generation: UInt64
    ) async -> DatabaseBootstrapOutcome {
        guard let ownerToClose = owner else { return intendedOutcome }
        let closeOutcome = await closeOwnerOperation(ownerToClose)
        switch closeOutcome {
        case .closed, .alreadyClosed:
            if owner === ownerToClose {
                owner = nil
            }
        case .failed:
            suspensionFailed = true
            return .recoveryRequired(.closeFailed)
        }

        guard isAttemptActive(generation) else {
            return interruptionOutcome()
        }
        return intendedOutcome
    }

    private func waitForBootstrapToStop() async {
        guard isBootstrapping else { return }
        await withCheckedContinuation { continuation in
            bootstrapStopWaiters.append(continuation)
        }
    }

    private func finishBootstrapAttempt() {
        isBootstrapping = false
        let waiters = bootstrapStopWaiters
        bootstrapStopWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func finishSuspension(with outcome: DatabaseCloseOutcome) {
        isSuspending = false
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
    }
}
