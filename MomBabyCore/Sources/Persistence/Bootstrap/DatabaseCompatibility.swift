import Foundation
import GRDB

enum DatabaseCompatibility: Sendable, Equatable {
    case empty
    case current
    case newer(version: Int)

    static func inspect(databaseURL: URL) throws -> DatabaseCompatibility {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .empty
        }

        let attributes = try fileManager.attributesOfItem(atPath: databaseURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue == 0 {
            return .empty
        }

        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: DatabaseConfigurationFactory.readOnly(
                label: "MomBaby.Database.Header"
            )
        )
        defer { try? queue.close() }

        return try queue.read { database in
            let applicationTableCount = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM sqlite_schema
                    WHERE type = 'table'
                      AND name NOT LIKE 'sqlite_%'
                      AND name <> 'grdb_migrations'
                    """
            ) ?? 0
            guard applicationTableCount > 0 else {
                return .empty
            }

            let applicationID = try Int.fetchOne(
                database,
                sql: "PRAGMA application_id"
            ) ?? 0
            guard applicationID == SchemaContract.applicationID else {
                throw DatabaseCompatibilityError.applicationIDMismatch
            }

            guard try database.tableExists("schema_metadata"),
                  let version = try Int.fetchOne(
                    database,
                    sql: "SELECT schema_version FROM schema_metadata WHERE singleton_slot = 1"
                  ) else {
                throw DatabaseCompatibilityError.metadataMissing
            }
            let mediaLayoutVersion = try Int.fetchOne(
                database,
                sql: "SELECT media_layout_version FROM schema_metadata WHERE singleton_slot = 1"
            )
            let fingerprint = try String.fetchOne(
                database,
                sql: "SELECT schema_fingerprint FROM schema_metadata WHERE singleton_slot = 1"
            )
            if version > SchemaContract.currentVersion {
                return .newer(version: version)
            }
            guard version == SchemaContract.currentVersion else {
                throw DatabaseCompatibilityError.unsupportedOlderSchema
            }
            guard mediaLayoutVersion == SchemaContract.mediaLayoutVersion else {
                throw DatabaseCompatibilityError.mediaLayoutVersionMismatch
            }
            guard fingerprint == SchemaContract.expectedFingerprint else {
                throw DatabaseCompatibilityError.fingerprintMismatch
            }
            return .current
        }
    }
}

enum DatabaseCompatibilityError: Error, Sendable {
    case applicationIDMismatch
    case metadataMissing
    case unsupportedOlderSchema
    case mediaLayoutVersionMismatch
    case fingerprintMismatch
}
