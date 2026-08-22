import CryptoKit
import Foundation
import GRDB

enum SchemaFingerprint {
    private static let unitSeparator = "\u{001F}"

    static func calculate(in database: Database) throws -> String {
        let objects = try SchemaObject.fetchAll(
            database,
            sql: """
                SELECT type, name, tbl_name, COALESCE(sql, '') AS sql
                FROM sqlite_schema
                WHERE name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                ORDER BY type, name
                """
        )

        let canonicalSchema = objects.map { object in
            [object.type, object.name, object.tableName, object.sql]
                .joined(separator: unitSeparator) + "\n"
        }.joined()
        let digest = SHA256.hash(data: Data(canonicalSchema.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct SchemaObject: FetchableRecord, Sendable {
    let type: String
    let name: String
    let tableName: String
    let sql: String

    init(row: Row) throws {
        type = row["type"]
        name = row["name"]
        tableName = row["tbl_name"]
        sql = row["sql"]
    }
}
