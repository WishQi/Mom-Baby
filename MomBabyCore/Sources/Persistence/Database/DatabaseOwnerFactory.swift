import Foundation
import GRDB

enum DatabaseOwnerFactory {
    static func production(at databaseURL: URL) throws -> DatabaseOwner {
        let configuration = DatabaseConfigurationFactory.readWrite(
            label: "MomBaby.Database"
        )
        let pool = try DatabasePool(
            path: databaseURL.path,
            configuration: configuration
        )
        return DatabaseOwner(writer: pool, expectedJournalMode: "wal")
    }

    /// A single shared in-memory connection for repository and migration tests.
    static func inMemory() throws -> DatabaseOwner {
        let configuration = DatabaseConfigurationFactory.readWrite(
            label: "MomBaby.Database.InMemory"
        )
        let queue = try DatabaseQueue(configuration: configuration)
        return DatabaseOwner(writer: queue, expectedJournalMode: "memory")
    }

    static func temporaryDisk(in directoryURL: URL) throws -> DatabaseOwner {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return try production(at: directoryURL.appendingPathComponent("store.sqlite"))
    }
}
