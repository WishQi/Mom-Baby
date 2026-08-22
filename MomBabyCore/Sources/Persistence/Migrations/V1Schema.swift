import Foundation

enum V1Schema {
    private static let connectionPragmaCount = 6

    static func authoritativeSQL() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "v1",
            withExtension: "sql"
        ) else {
            throw V1SchemaError.resourceMissing
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    static func migrationSQL() throws -> String {
        let source = try authoritativeSQL()
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        guard lines.count > connectionPragmaCount else {
            throw V1SchemaError.resourceMalformed
        }

        let expectedPragmas = [
            "PRAGMA application_id = 1296187993; -- 0x4D424259, \"MBBY\"",
            "PRAGMA foreign_keys = ON;",
            "PRAGMA journal_mode = WAL;",
            "PRAGMA synchronous = FULL;",
            "PRAGMA secure_delete = ON;",
            "PRAGMA temp_store = MEMORY;",
        ]
        guard zip(lines.prefix(connectionPragmaCount), expectedPragmas)
            .allSatisfy({ String($0.0) == $0.1 }) else {
            throw V1SchemaError.resourceMalformed
        }

        return lines.dropFirst(connectionPragmaCount).joined(separator: "\n")
    }
}

enum V1SchemaError: Error, Sendable {
    case resourceMissing
    case resourceMalformed
}
