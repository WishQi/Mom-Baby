import CryptoKit
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Database validation")
struct DatabaseValidationTests {
    @Test("DB-APPLICATION-ID-001 keeps ASCII, hexadecimal, and decimal forms aligned")
    func applicationIDContractIsMBBY() {
        let bytes = (0..<4).reversed().map { shift in
            UInt8((SchemaContract.applicationID >> (shift * 8)) & 0xff)
        }

        #expect(SchemaContract.applicationID == 1_296_187_993)
        #expect(SchemaContract.applicationID == 0x4D42_4259)
        #expect(String(decoding: bytes, as: UTF8.self) == "MBBY")
    }

    @Test("DB-SCHEMA-RESOURCE-001 contains only both authoritative SQL blocks")
    func authoritativeResourceIsCompleteSQL() throws {
        let sql = try V1Schema.authoritativeSQL()

        #expect(sql.hasPrefix("PRAGMA application_id = 1296187993; -- 0x4D424259, \"MBBY\""))
        #expect(sql.contains("CREATE TABLE active_resource_lock"))
        #expect(sql.contains("CREATE TABLE nursing_side_detail"))
        #expect(sql.contains("CREATE TRIGGER active_module_cannot_be_disabled"))
        #expect(!sql.contains("```"))
        let digest = SHA256.hash(data: Data(sql.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(
            digest == "10bc8c43fa66f89fbc668b5c0f969a6ba001128cf16c15d278f8076d7215e087"
        )
    }

    @Test("DB-FINGERPRINT-001 detects schema drift")
    func fingerprintRejectsUnexpectedSchemaObject() async throws {
        let owner = try await migratedInMemoryOwner()
        _ = try await DatabaseValidator.validate(owner)
        try await owner.write { database in
            try database.execute(sql: "CREATE TABLE unexpected_schema_object (id INTEGER)")
        }

        do {
            _ = try await DatabaseValidator.validate(owner)
            Issue.record("Expected fingerprint validation to fail")
        } catch DatabaseValidationError.fingerprintMismatch {
            // Expected.
        }
        #expect(await owner.close() == .closed)
    }

    @Test("DB-FK-001 foreign_key_check rejects latent violations")
    func foreignKeyCheckRejectsViolation() async throws {
        let owner = try await migratedInMemoryOwner()
        try await owner.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA foreign_keys = OFF")
            try database.execute(sql: """
                INSERT INTO local_actor (
                    id, local_vault_id, guardian_declared, created_at_ms, updated_at_ms
                ) VALUES (
                    '09cb1050-cf33-45ca-bc09-15bbd8aec177',
                    '3dc7f0c9-7801-4994-af81-f6b875757c66',
                    1, 1, 1
                )
                """)
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        do {
            _ = try await DatabaseValidator.validate(owner)
            Issue.record("Expected foreign key validation to fail")
        } catch DatabaseValidationError.foreignKeyCheckFailed {
            // Expected.
        }
        #expect(await owner.close() == .closed)
    }

    @Test("DB-MIGRATION-HISTORY-001 rejects migration metadata drift")
    func migrationHistoryMismatchFailsValidation() async throws {
        let owner = try await migratedInMemoryOwner()
        try await owner.write { database in
            try database.execute(sql: "UPDATE grdb_migrations SET identifier = 'unexpected'")
        }

        do {
            _ = try await DatabaseValidator.validate(owner)
            Issue.record("Expected migration history validation to fail")
        } catch DatabaseValidationError.migrationHistoryMismatch {
            // Expected.
        }
        #expect(await owner.close() == .closed)
    }
}

private func migratedInMemoryOwner() async throws -> DatabaseOwner {
    let owner = try DatabaseOwnerFactory.inMemory()
    let migrator = try AppDatabaseMigrator(
        installedAtMilliseconds: 1_725_004_800_000
    )
    try await owner.migrate(migrator.migrator)
    return owner
}
