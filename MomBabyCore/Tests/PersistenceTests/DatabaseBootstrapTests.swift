import Foundation
import GRDB
import Testing

import Domain
@testable import Persistence

@Suite("Database bootstrap")
struct DatabaseBootstrapTests {
    @Test("DB-SCHEMA-EMPTY-001 creates and validates the complete v1 schema")
    func schemaFromEmptyInMemoryDatabase() async throws {
        let recorder = PhaseRecorder()
        let coordinator = DatabaseBootstrapCoordinator.inMemory(
            dependencies: testDependencies()
        )

        let outcome = await coordinator.bootstrap { phase in
            await recorder.append(phase)
        }
        let report = try readyReport(from: outcome)

        #expect(report.applicationID == SchemaContract.applicationID)
        #expect(report.schemaVersion == SchemaContract.currentVersion)
        #expect(report.schemaFingerprint == SchemaContract.expectedFingerprint)
        #expect(report.tableCount == 44)
        #expect(report.indexCount == 36)
        #expect(report.triggerCount == 86)
        #expect(report.quickCheck == "ok")
        #expect(report.integrityCheck == "ok")
        #expect(report.foreignKeyViolationCount == 0)
        #expect(report.pragmas.journalMode == "memory")
        #expect(
            await recorder.values == [
                .locatingVault,
                .validatingHeader,
                .preparingMigration,
                .migratingSchema,
                .migratingFiles,
                .validatingResult,
                .ready,
            ]
        )

        #expect(await coordinator.close() == .closed)
    }

    @Test("DB-SCHEMA-DISK-001 uses WAL and is idempotent on temporary disk")
    func temporaryDiskDatabaseUsesWALAndReopens() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: testDependencies()
        )
        let firstReport = try readyReport(from: await first.bootstrap())
        #expect(firstReport.pragmas.journalMode == "wal")
        #expect(firstReport.pragmas.foreignKeysEnabled)
        #expect(firstReport.pragmas.synchronousLevel == 2)
        #expect(firstReport.pragmas.secureDeleteEnabled)
        #expect(firstReport.pragmas.temporaryStore == 2)
        #expect(firstReport.pragmas.busyTimeoutMilliseconds == 5_000)
        #expect(await first.close() == .closed)

        let second = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: testDependencies()
        )
        let secondReport = try readyReport(from: await second.bootstrap())
        #expect(secondReport == firstReport)
        #expect(await second.close() == .closed)
    }

    @Test("DB-BOOT-PROTECTED-001 stops before opening unavailable protected data")
    func protectedDataUnavailableDoesNotBootstrap() async {
        let coordinator = DatabaseBootstrapCoordinator.inMemory(
            dependencies: testDependencies()
        )

        let outcome = await coordinator.bootstrap(protectedDataAvailable: false)
        #expect(outcome == .waitingForProtectedData)
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-PROVISION-001 publishes CurrentVault only after validation")
    func firstInstallPublishesValidatedVault() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )

        _ = try readyReport(from: await coordinator.bootstrap())

        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        let pointer = root.appendingPathComponent("CurrentVault")
        let marker = root.appendingPathComponent("ProvisioningVault")
        let expectedVaultID = "92367a9a-7ad0-4b39-87d5-16575b08d7e9"
        #expect(
            try String(contentsOf: pointer, encoding: .utf8) ==
                "active:\(expectedVaultID)"
        )
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let database = root
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(expectedVaultID, isDirectory: true)
            .appendingPathComponent("store.sqlite")
        #expect(try databaseFileSize(database) > 0)
        #expect(await coordinator.close() == .closed)
    }

    @Test("DB-VAULT-POINTER-LOSS-001 never hides an existing vault")
    func missingPointerWithExistingVaultFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        _ = try readyReport(from: await first.bootstrap())
        #expect(await first.close() == .closed)

        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        let pointer = root.appendingPathComponent("CurrentVault")
        let vaults = root.appendingPathComponent("Vaults", isDirectory: true)
        let originalVaultIDs = try FileManager.default.contentsOfDirectory(atPath: vaults.path)
        try FileManager.default.removeItem(at: pointer)

        let second = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(await second.bootstrap() == .recoveryRequired(.invalidVault))
        #expect(!FileManager.default.fileExists(atPath: pointer.path))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: vaults.path) ==
                originalVaultIDs
        )
        #expect(await second.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-TARGET-MISSING-001 never recreates an active pointer target")
    func activePointerWithMissingTargetFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        let vaults = root.appendingPathComponent("Vaults", isDirectory: true)
        let vaultID = "92367a9a-7ad0-4b39-87d5-16575b08d7e9"
        try FileManager.default.createDirectory(at: vaults, withIntermediateDirectories: true)
        try Data("active:\(vaultID)".utf8).write(
            to: root.appendingPathComponent("CurrentVault")
        )

        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(await coordinator.bootstrap() == .recoveryRequired(.invalidVault))
        #expect(
            !FileManager.default.fileExists(
                atPath: vaults.appendingPathComponent(vaultID).path
            )
        )
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-STORE-MISSING-001 never creates a missing active store")
    func activePointerWithMissingStoreFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = try createActiveVaultLayout(in: directory, emptyStore: nil)

        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(await coordinator.bootstrap() == .recoveryRequired(.invalidVault))
        #expect(!FileManager.default.fileExists(atPath: layout.databaseURL.path))
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-ZERO-STORE-001 rejects a truncated active database")
    func activePointerWithZeroByteStoreFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = try createActiveVaultLayout(in: directory, emptyStore: true)

        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(await coordinator.bootstrap() == .recoveryRequired(.invalidVault))
        #expect(try databaseFileSize(layout.databaseURL) == 0)
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-JOURNAL-001 resumes provisioning without early publication")
    func failedMigrationLeavesResumableUnpublishedVault() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = DatabaseBootstrapCoordinator(
            storage: .live(applicationSupportDirectory: directory),
            dependencies: testDependencies(),
            makeMigrator: { _ in
                var migrator = DatabaseMigrator()
                migrator.registerMigration("forced_failure") { _ in
                    throw ForcedMigrationError.expected
                }
                return migrator
            }
        )

        #expect(await failing.bootstrap() == .recoveryRequired(.migrationFailed))
        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        let pointer = root.appendingPathComponent("CurrentVault")
        let marker = root.appendingPathComponent("ProvisioningVault")
        #expect(!FileManager.default.fileExists(atPath: pointer.path))
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(await failing.close() == .alreadyClosed)

        let resumed = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        _ = try readyReport(from: await resumed.bootstrap())
        #expect(FileManager.default.fileExists(atPath: pointer.path))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(await resumed.close() == .closed)
    }

    @Test("DB-BOOT-NEWER-001 rejects a newer schema without migrating")
    func newerSchemaFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let databaseURL = directory.appendingPathComponent("store.sqlite")
        let queue = try DatabaseQueue(path: databaseURL.path)
        try await queue.writeWithoutTransaction { database in
            try database.execute(
                sql: "PRAGMA application_id = \(SchemaContract.applicationID)"
            )
            try database.execute(sql: """
                CREATE TABLE schema_metadata (
                    singleton_slot INTEGER PRIMARY KEY,
                    schema_version INTEGER NOT NULL,
                    media_layout_version INTEGER NOT NULL,
                    schema_fingerprint TEXT NOT NULL
                ) STRICT;
                """)
            try database.execute(
                sql: "INSERT INTO schema_metadata VALUES (1, 2, 1, ?)",
                arguments: [SchemaContract.expectedFingerprint]
            )
        }
        try queue.close()

        let coordinator = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: testDependencies()
        )
        let outcome = await coordinator.bootstrap()
        #expect(
            outcome == .newerSchema(
                found: 2,
                supported: SchemaContract.currentVersion
            )
        )
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-UNAVAILABLE-001 maps an unavailable pointer to recovery")
    func unavailableVaultPointerRequiresRecovery() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("unavailable:92367a9a-7ad0-4b39-87d5-16575b08d7e9".utf8).write(
            to: root.appendingPathComponent("CurrentVault")
        )

        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(
            await coordinator.bootstrap() == .recoveryRequired(.vaultUnavailable)
        )
        #expect(await coordinator.close() == .alreadyClosed)

        try Data("unavailable:not-a-canonical-operation-id".utf8).write(
            to: root.appendingPathComponent("CurrentVault"),
            options: .atomic
        )
        let malformedCoordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(
            await malformedCoordinator.bootstrap() == .recoveryRequired(.invalidVault)
        )
        #expect(await malformedCoordinator.close() == .alreadyClosed)
    }

    @Test("DB-VAULT-SYMLINK-001 rejects a CurrentVault path that escapes through a symlink")
    func symbolicLinkVaultFailsClosed() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
        let vaults = root.appendingPathComponent("Vaults", isDirectory: true)
        let outside = directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vaults,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let vaultID = "92367a9a-7ad0-4b39-87d5-16575b08d7e9"
        try Data("active:\(vaultID)".utf8).write(
            to: root.appendingPathComponent("CurrentVault")
        )
        try FileManager.default.createSymbolicLink(
            at: vaults.appendingPathComponent(vaultID),
            withDestinationURL: outside
        )

        let coordinator = DatabaseBootstrapCoordinator.live(
            applicationSupportDirectory: directory,
            dependencies: testDependencies()
        )
        #expect(await coordinator.bootstrap() == .recoveryRequired(.invalidVault))
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-MIGRATION-FAILURE-001 reports and rolls back a failed migration")
    func failedMigrationRollsBack() async throws {
        let owner = try DatabaseOwnerFactory.inMemory()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("forced_failure") { database in
            try database.execute(sql: "CREATE TABLE should_rollback (id INTEGER)")
            throw ForcedMigrationError.expected
        }

        do {
            try await owner.migrate(migrator)
            Issue.record("Expected migration to fail")
        } catch ForcedMigrationError.expected {
            // Expected.
        }

        let tableExists = try await owner.read { database in
            try database.tableExists("should_rollback")
        }
        #expect(!tableExists)
        #expect(await owner.close() == .closed)
    }

    @Test("DB-BOOT-FAILURE-001 maps migration failures to recovery")
    func coordinatorMapsMigrationFailure() async {
        let coordinator = DatabaseBootstrapCoordinator(
            storage: .inMemory,
            dependencies: testDependencies(),
            makeMigrator: { _ in
                var migrator = DatabaseMigrator()
                migrator.registerMigration("forced_failure") { _ in
                    throw ForcedMigrationError.expected
                }
                return migrator
            }
        )

        let outcome = await coordinator.bootstrap()
        #expect(outcome == .recoveryRequired(.migrationFailed))
        #expect(await coordinator.close() == .alreadyClosed)
    }

    @Test("DB-LIFECYCLE-001 suspends and reopens the same database")
    func protectedDataSuspendCanBootstrapAgain() async throws {
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: testDependencies()
        )

        _ = try readyReport(from: await coordinator.bootstrap())
        #expect(await coordinator.suspendForProtectedData() == .closed)
        _ = try readyReport(from: await coordinator.bootstrap())
        #expect(await coordinator.close() == .closed)
    }

    @Test(
        "DB-LIFECYCLE-REVOKE-001 revokes bootstrap at every progress suspension point",
        arguments: [
            DatabaseBootstrapPhase.locatingVault,
            .validatingHeader,
            .preparingMigration,
            .migratingSchema,
            .migratingFiles,
            .validatingResult,
            .ready,
        ]
    )
    func protectedDataSuspendRevokesEveryPhase(
        phaseToPause: DatabaseBootstrapPhase
    ) async throws {
        let gate = BootstrapPhaseGate(target: phaseToPause)
        let suspensionSignal = AsyncStream<Void>.makeStream()
        var suspensionIterator = suspensionSignal.stream.makeAsyncIterator()
        let coordinator = DatabaseBootstrapCoordinator(
            storage: .inMemory,
            dependencies: testDependencies(),
            suspensionStarted: {
                suspensionSignal.continuation.yield()
            }
        )

        let bootstrapTask = Task {
            await coordinator.bootstrap { phase in
                await gate.pauseIfTarget(phase)
            }
        }
        await gate.waitUntilReached()
        let suspensionTask = Task {
            await coordinator.suspendForProtectedData()
        }
        _ = await suspensionIterator.next()
        await gate.release()

        #expect(await bootstrapTask.value == .waitingForProtectedData)
        #expect(await suspensionTask.value != .failed)
        _ = try readyReport(from: await coordinator.bootstrap())
        #expect(await coordinator.close() == .closed)
    }

    @Test("DB-LIFECYCLE-CLOSE-FAIL-001 prevents a second owner after close failure")
    func closeFailureFailsClosedUntilCloseSucceeds() async throws {
        let closeController = FailFirstCloseController()
        let coordinator = DatabaseBootstrapCoordinator(
            storage: .inMemory,
            dependencies: testDependencies(),
            closeOwner: { owner in
                await closeController.close(owner)
            }
        )

        _ = try readyReport(from: await coordinator.bootstrap())
        #expect(await coordinator.suspendForProtectedData() == .failed)
        #expect(await coordinator.bootstrap() == .recoveryRequired(.closeFailed))
        #expect(await coordinator.close() == .closed)
    }
}

private actor PhaseRecorder {
    private(set) var values: [DatabaseBootstrapPhase] = []

    func append(_ phase: DatabaseBootstrapPhase) {
        values.append(phase)
    }
}

private actor BootstrapPhaseGate {
    private let target: DatabaseBootstrapPhase
    private var didReachTarget = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(target: DatabaseBootstrapPhase) {
        self.target = target
    }

    func pauseIfTarget(_ phase: DatabaseBootstrapPhase) async {
        guard phase == target else { return }
        didReachTarget = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilReached() async {
        guard !didReachTarget else { return }
        await withCheckedContinuation { continuation in
            reachWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor FailFirstCloseController {
    private var shouldFail = true

    func close(_ owner: DatabaseOwner) async -> DatabaseCloseOutcome {
        if shouldFail {
            shouldFail = false
            return .failed
        }
        return await owner.close()
    }
}

private enum ForcedMigrationError: Error {
    case expected
}

private func readyReport(
    from outcome: DatabaseBootstrapOutcome
) throws -> DatabaseValidationReport {
    guard case .ready(let report) = outcome else {
        throw UnexpectedBootstrapOutcome(outcome: outcome)
    }
    return report
}

private struct UnexpectedBootstrapOutcome: Error {
    let outcome: DatabaseBootstrapOutcome
}

private func testDependencies() -> PersistenceDependencies {
    PersistenceDependencies(
        clock: FixedClock(now: Date(timeIntervalSince1970: 1_725_004_800)),
        uuid: FixedUUIDGenerator(
            uuid: UUID(uuidString: "92367a9a-7ad0-4b39-87d5-16575b08d7e9")!
        ),
        logger: DisabledPrivacyLogger()
    )
}

private struct FixedClock: AppClock {
    let now: Date
}

private struct FixedUUIDGenerator: UUIDGenerating {
    let uuid: UUID

    func makeUUID() -> UUID { uuid }
}

private func uniqueTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MomBabyCoreTests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private struct ActiveVaultLayout {
    let databaseURL: URL
}

private func createActiveVaultLayout(
    in directory: URL,
    emptyStore: Bool?
) throws -> ActiveVaultLayout {
    let vaultID = "92367a9a-7ad0-4b39-87d5-16575b08d7e9"
    let root = directory.appendingPathComponent("MomBaby", isDirectory: true)
    let vault = root
        .appendingPathComponent("Vaults", isDirectory: true)
        .appendingPathComponent(vaultID, isDirectory: true)
    try FileManager.default.createDirectory(
        at: vault.appendingPathComponent("staging", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: vault.appendingPathComponent("trash", isDirectory: true),
        withIntermediateDirectories: true
    )
    let databaseURL = vault.appendingPathComponent("store.sqlite")
    if let emptyStore {
        let contents = emptyStore ? Data() : Data("not-a-sqlite-database".utf8)
        try contents.write(to: databaseURL)
    }
    try Data("active:\(vaultID)".utf8).write(
        to: root.appendingPathComponent("CurrentVault")
    )
    return ActiveVaultLayout(databaseURL: databaseURL)
}

private func databaseFileSize(_ url: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
}
