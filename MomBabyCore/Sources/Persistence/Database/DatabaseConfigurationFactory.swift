import Foundation
import GRDB

enum DatabaseConfigurationFactory {
    static let busyTimeoutSeconds: TimeInterval = 5
    static let maximumReaderCount = 4

    static func readWrite(label: String) -> Configuration {
        var configuration = Configuration()
        configuration.label = label
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(busyTimeoutSeconds)
        configuration.maximumReaderCount = maximumReaderCount
        configuration.publicStatementArguments = false
        configuration.prepareDatabase { database in
            // DatabasePool gives readers its own default busy handler unless
            // each connection explicitly sets the PRAGMA during preparation.
            try database.execute(sql: "PRAGMA busy_timeout = 5000")
            try database.execute(sql: "PRAGMA synchronous = FULL")
            try database.execute(sql: "PRAGMA secure_delete = ON")
            try database.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        return configuration
    }

    static func readOnly(label: String) -> Configuration {
        var configuration = Configuration()
        configuration.label = label
        configuration.readonly = true
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(busyTimeoutSeconds)
        configuration.publicStatementArguments = false
        return configuration
    }
}
