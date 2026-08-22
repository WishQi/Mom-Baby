import GRDB
import Testing

@testable import Persistence

@Suite("Active device installation version contract")
struct DeviceInstallationValidationTests {
    @Test("Pre-onboarding database may have no device installation")
    func zeroRowsPassValidation() async throws {
        let owner = try await migratedOwner()

        _ = try await DatabaseValidator.validate(owner)
        let installationCount = try await owner.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM device_installation")
        }

        #expect(installationCount == 0)
        #expect(await owner.close() == .closed)
    }

    @Test("Matching active installation passes validation")
    func matchingActiveInstallationPassesValidation() async throws {
        let owner = try await migratedOwner()
        try await insertInstallation(in: owner)

        _ = try await DatabaseValidator.validate(owner)

        #expect(await owner.close() == .closed)
    }

    @Test("Active installation schema version drift fails closed")
    func schemaVersionDriftFailsValidation() async throws {
        let owner = try await migratedOwner()
        try await insertInstallation(
            in: owner,
            schemaVersion: SchemaContract.currentVersion + 1
        )

        await expectValidationError(
            .activeInstallationSchemaVersionMismatch,
            from: owner
        )
        #expect(await owner.close() == .closed)
    }

    @Test("Active installation media layout version drift fails closed")
    func mediaLayoutVersionDriftFailsValidation() async throws {
        let owner = try await migratedOwner()
        try await insertInstallation(
            in: owner,
            mediaLayoutVersion: SchemaContract.mediaLayoutVersion + 1
        )

        await expectValidationError(
            .activeInstallationMediaLayoutVersionMismatch,
            from: owner
        )
        #expect(await owner.close() == .closed)
    }

    @Test("Active installation fingerprint drift fails closed")
    func fingerprintDriftFailsValidation() async throws {
        let owner = try await migratedOwner()
        try await insertInstallation(
            in: owner,
            schemaFingerprint: String(repeating: "f", count: 64)
        )

        await expectValidationError(
            .activeInstallationFingerprintMismatch,
            from: owner
        )
        #expect(await owner.close() == .closed)
    }

    @Test("Historical installation version drift is not active runtime state")
    func replacedInstallationDoesNotBlockValidation() async throws {
        let owner = try await migratedOwner()
        try await insertInstallation(
            in: owner,
            state: "replaced",
            schemaVersion: SchemaContract.currentVersion + 1,
            mediaLayoutVersion: SchemaContract.mediaLayoutVersion + 1,
            schemaFingerprint: String(repeating: "f", count: 64)
        )

        _ = try await DatabaseValidator.validate(owner)

        #expect(await owner.close() == .closed)
    }
}

private func migratedOwner() async throws -> DatabaseOwner {
    let owner = try DatabaseOwnerFactory.inMemory()
    let migrator = try AppDatabaseMigrator(
        installedAtMilliseconds: 1_725_004_800_000
    )
    try await owner.migrate(migrator.migrator)
    return owner
}

private func insertInstallation(
    in owner: DatabaseOwner,
    state: String = "active",
    schemaVersion: Int = SchemaContract.currentVersion,
    mediaLayoutVersion: Int = SchemaContract.mediaLayoutVersion,
    schemaFingerprint: String = SchemaContract.expectedFingerprint
) async throws {
    try await owner.write { database in
        try database.execute(
            sql: """
                INSERT INTO local_vault (
                    id, state, created_at_ms, updated_at_ms
                ) VALUES (?, 'active', ?, ?)
                """,
            arguments: [
                "3dc7f0c9-7801-4994-af81-f6b875757c66",
                1_725_004_800_000,
                1_725_004_800_000,
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO device_installation (
                    id,
                    local_vault_id,
                    state,
                    schema_version,
                    media_layout_version,
                    schema_fingerprint,
                    restore_sentinel_hash,
                    backup_policy_generation,
                    created_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                "09cb1050-cf33-45ca-bc09-15bbd8aec177",
                "3dc7f0c9-7801-4994-af81-f6b875757c66",
                state,
                schemaVersion,
                mediaLayoutVersion,
                schemaFingerprint,
                String(repeating: "a", count: 64),
                1,
                1_725_004_800_000,
            ]
        )
    }
}

private func expectValidationError(
    _ expectedError: DatabaseValidationError,
    from owner: DatabaseOwner
) async {
    do {
        _ = try await DatabaseValidator.validate(owner)
        Issue.record("Expected active installation contract validation to fail")
    } catch let error as DatabaseValidationError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Unexpected validation error: \(error)")
    }
}
