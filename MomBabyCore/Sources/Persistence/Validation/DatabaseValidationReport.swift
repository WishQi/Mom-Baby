/// Read-back values for connection settings required by the v1 contract.
public struct DatabasePragmaReport: Sendable, Equatable {
    public let foreignKeysEnabled: Bool
    public let journalMode: String
    public let synchronousLevel: Int
    public let secureDeleteEnabled: Bool
    public let temporaryStore: Int
    public let busyTimeoutMilliseconds: Int

    public init(
        foreignKeysEnabled: Bool,
        journalMode: String,
        synchronousLevel: Int,
        secureDeleteEnabled: Bool,
        temporaryStore: Int,
        busyTimeoutMilliseconds: Int
    ) {
        self.foreignKeysEnabled = foreignKeysEnabled
        self.journalMode = journalMode
        self.synchronousLevel = synchronousLevel
        self.secureDeleteEnabled = secureDeleteEnabled
        self.temporaryStore = temporaryStore
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
    }
}

/// A Sendable snapshot produced only after all database validation gates pass.
public struct DatabaseValidationReport: Sendable, Equatable {
    public let applicationID: Int
    public let schemaVersion: Int
    public let schemaFingerprint: String
    public let quickCheck: String
    public let integrityCheck: String
    public let foreignKeyViolationCount: Int
    public let tableCount: Int
    public let indexCount: Int
    public let triggerCount: Int
    public let pragmas: DatabasePragmaReport

    public init(
        applicationID: Int,
        schemaVersion: Int,
        schemaFingerprint: String,
        quickCheck: String,
        integrityCheck: String,
        foreignKeyViolationCount: Int,
        tableCount: Int,
        indexCount: Int,
        triggerCount: Int,
        pragmas: DatabasePragmaReport
    ) {
        self.applicationID = applicationID
        self.schemaVersion = schemaVersion
        self.schemaFingerprint = schemaFingerprint
        self.quickCheck = quickCheck
        self.integrityCheck = integrityCheck
        self.foreignKeyViolationCount = foreignKeyViolationCount
        self.tableCount = tableCount
        self.indexCount = indexCount
        self.triggerCount = triggerCount
        self.pragmas = pragmas
    }
}
