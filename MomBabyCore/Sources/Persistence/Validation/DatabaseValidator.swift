import GRDB

enum DatabaseValidator {
    static func validate(_ owner: DatabaseOwner) async throws -> DatabaseValidationReport {
        try await owner.read { database in
            let applicationID = try requiredInt(
                database,
                sql: "PRAGMA application_id"
            )
            let schemaVersion = try requiredInt(
                database,
                sql: "SELECT schema_version FROM schema_metadata WHERE singleton_slot = 1"
            )
            let storedFingerprint = try requiredString(
                database,
                sql: "SELECT schema_fingerprint FROM schema_metadata WHERE singleton_slot = 1"
            )
            let mediaLayoutVersion = try requiredInt(
                database,
                sql: "SELECT media_layout_version FROM schema_metadata WHERE singleton_slot = 1"
            )
            let appliedMigrations = try String.fetchAll(
                database,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
            let fingerprint = try SchemaFingerprint.calculate(in: database)
            let quickCheckRows = try String.fetchAll(database, sql: "PRAGMA quick_check")
            let integrityCheckRows = try String.fetchAll(database, sql: "PRAGMA integrity_check")
            let foreignKeyViolations = try Row.fetchAll(
                database,
                sql: "PRAGMA foreign_key_check"
            )
            let tableCount = try schemaObjectCount(database, type: "table")
            let indexCount = try schemaObjectCount(database, type: "index")
            let triggerCount = try schemaObjectCount(database, type: "trigger")
            let pragmas = try readPragmas(database)

            guard applicationID == SchemaContract.applicationID else {
                throw DatabaseValidationError.applicationIDMismatch
            }
            guard schemaVersion == SchemaContract.currentVersion else {
                throw DatabaseValidationError.schemaVersionMismatch
            }
            guard mediaLayoutVersion == SchemaContract.mediaLayoutVersion else {
                throw DatabaseValidationError.mediaLayoutVersionMismatch
            }
            guard appliedMigrations == [SchemaContract.migrationIdentifier] else {
                throw DatabaseValidationError.migrationHistoryMismatch
            }
            guard storedFingerprint == SchemaContract.expectedFingerprint,
                  fingerprint == SchemaContract.expectedFingerprint else {
                throw DatabaseValidationError.fingerprintMismatch
            }
            try validateActiveInstallationContract(
                database,
                schemaVersion: schemaVersion,
                mediaLayoutVersion: mediaLayoutVersion,
                schemaFingerprint: storedFingerprint
            )
            guard quickCheckRows == ["ok"] else {
                throw DatabaseValidationError.quickCheckFailed
            }
            guard integrityCheckRows == ["ok"] else {
                throw DatabaseValidationError.integrityCheckFailed
            }
            guard foreignKeyViolations.isEmpty else {
                throw DatabaseValidationError.foreignKeyCheckFailed
            }
            guard tableCount == SchemaContract.expectedTableCount,
                  indexCount == SchemaContract.expectedIndexCount,
                  triggerCount == SchemaContract.expectedTriggerCount else {
                throw DatabaseValidationError.schemaObjectCountMismatch
            }
            guard pragmas.foreignKeysEnabled,
                  pragmas.journalMode == owner.expectedJournalMode,
                  pragmas.synchronousLevel == 2,
                  pragmas.secureDeleteEnabled,
                  pragmas.temporaryStore == 2,
                  pragmas.busyTimeoutMilliseconds == 5_000 else {
                throw DatabaseValidationError.pragmaMismatch
            }

            return DatabaseValidationReport(
                applicationID: applicationID,
                schemaVersion: schemaVersion,
                schemaFingerprint: fingerprint,
                quickCheck: quickCheckRows[0],
                integrityCheck: integrityCheckRows[0],
                foreignKeyViolationCount: foreignKeyViolations.count,
                tableCount: tableCount,
                indexCount: indexCount,
                triggerCount: triggerCount,
                pragmas: pragmas
            )
        }
    }

    static func readPragmas(_ database: Database) throws -> DatabasePragmaReport {
        DatabasePragmaReport(
            foreignKeysEnabled: try requiredInt(database, sql: "PRAGMA foreign_keys") == 1,
            journalMode: try requiredString(database, sql: "PRAGMA journal_mode").lowercased(),
            synchronousLevel: try requiredInt(database, sql: "PRAGMA synchronous"),
            secureDeleteEnabled: try requiredInt(database, sql: "PRAGMA secure_delete") == 1,
            temporaryStore: try requiredInt(database, sql: "PRAGMA temp_store"),
            busyTimeoutMilliseconds: try requiredInt(database, sql: "PRAGMA busy_timeout")
        )
    }

    private static func schemaObjectCount(
        _ database: Database,
        type: String
    ) throws -> Int {
        try requiredInt(
            database,
            sql: """
                SELECT COUNT(*)
                FROM sqlite_schema
                WHERE type = ?
                  AND name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                """,
            arguments: [type]
        )
    }

    /// Onboarding owns creation and version updates for `device_installation`.
    /// A freshly migrated, pre-onboarding database therefore has no active row.
    /// Once one exists, it must agree with the already-validated schema metadata.
    private static func validateActiveInstallationContract(
        _ database: Database,
        schemaVersion: Int,
        mediaLayoutVersion: Int,
        schemaFingerprint: String
    ) throws {
        let schemaVersionMismatchCount = try requiredInt(
            database,
            sql: """
                SELECT COUNT(*)
                FROM device_installation
                WHERE state = 'active' AND schema_version <> ?
                """,
            arguments: [schemaVersion]
        )
        guard schemaVersionMismatchCount == 0 else {
            throw DatabaseValidationError.activeInstallationSchemaVersionMismatch
        }

        let mediaLayoutVersionMismatchCount = try requiredInt(
            database,
            sql: """
                SELECT COUNT(*)
                FROM device_installation
                WHERE state = 'active' AND media_layout_version <> ?
                """,
            arguments: [mediaLayoutVersion]
        )
        guard mediaLayoutVersionMismatchCount == 0 else {
            throw DatabaseValidationError.activeInstallationMediaLayoutVersionMismatch
        }

        let fingerprintMismatchCount = try requiredInt(
            database,
            sql: """
                SELECT COUNT(*)
                FROM device_installation
                WHERE state = 'active' AND schema_fingerprint <> ?
                """,
            arguments: [schemaFingerprint]
        )
        guard fingerprintMismatchCount == 0 else {
            throw DatabaseValidationError.activeInstallationFingerprintMismatch
        }
    }

    private static func requiredInt(
        _ database: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> Int {
        guard let value = try Int.fetchOne(database, sql: sql, arguments: arguments) else {
            throw DatabaseValidationError.missingValue
        }
        return value
    }

    private static func requiredString(
        _ database: Database,
        sql: String
    ) throws -> String {
        guard let value = try String.fetchOne(database, sql: sql) else {
            throw DatabaseValidationError.missingValue
        }
        return value
    }
}

enum DatabaseValidationError: Error, Sendable {
    case missingValue
    case applicationIDMismatch
    case schemaVersionMismatch
    case mediaLayoutVersionMismatch
    case migrationHistoryMismatch
    case fingerprintMismatch
    case activeInstallationSchemaVersionMismatch
    case activeInstallationMediaLayoutVersionMismatch
    case activeInstallationFingerprintMismatch
    case quickCheckFailed
    case integrityCheckFailed
    case foreignKeyCheckFailed
    case schemaObjectCountMismatch
    case pragmaMismatch
}
