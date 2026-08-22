import GRDB

struct AppDatabaseMigrator: Sendable {
    let migrator: DatabaseMigrator

    init(installedAtMilliseconds: Int64) throws {
        let migrationSQL = try V1Schema.migrationSQL()
        var migrator = DatabaseMigrator()
        migrator.registerMigration(SchemaContract.migrationIdentifier) { database in
            try database.execute(
                sql: "PRAGMA application_id = \(SchemaContract.applicationID)"
            )
            try database.execute(sql: migrationSQL)

            let fingerprint = try SchemaFingerprint.calculate(in: database)
            guard fingerprint == SchemaContract.expectedFingerprint else {
                throw AppDatabaseMigrationError.fingerprintMismatch
            }

            try database.execute(
                sql: """
                    INSERT INTO schema_metadata (
                        singleton_slot,
                        application_id,
                        schema_version,
                        media_layout_version,
                        schema_fingerprint,
                        installed_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    1,
                    SchemaContract.applicationID,
                    SchemaContract.currentVersion,
                    SchemaContract.mediaLayoutVersion,
                    fingerprint,
                    installedAtMilliseconds,
                ]
            )
        }
        self.migrator = migrator
    }
}

enum AppDatabaseMigrationError: Error, Sendable {
    case fingerprintMismatch
}
