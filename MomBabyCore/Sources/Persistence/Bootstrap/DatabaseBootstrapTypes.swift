/// Observable milestones emitted while the local database is prepared.
public enum DatabaseBootstrapPhase: String, CaseIterable, Sendable {
    case waitingForProtectedData = "waiting_for_protected_data"
    case locatingVault = "locating_vault"
    case validatingHeader = "validating_header"
    case preparingMigration = "preparing_migration"
    case migratingSchema = "migrating_schema"
    case migratingFiles = "migrating_files"
    case validatingResult = "validating_result"
    case ready
}

/// Stable, privacy-safe recovery categories for UI decisions.
public enum DatabaseRecoveryReason: String, Error, Sendable {
    case invalidVault = "invalid_vault"
    case vaultUnavailable = "vault_unavailable"
    case openFailed = "open_failed"
    case migrationFailed = "migration_failed"
    case validationFailed = "validation_failed"
    case closeFailed = "close_failed"
    case alreadyInProgress = "already_in_progress"
    case closed
}

/// The terminal result of one bootstrap attempt.
public enum DatabaseBootstrapOutcome: Sendable, Equatable {
    case ready(DatabaseValidationReport)
    case waitingForProtectedData
    case protectionBlocked
    case newerSchema(found: Int, supported: Int)
    case recoveryRequired(DatabaseRecoveryReason)
    case readOnlyExport
}

/// The result of closing the single database owner.
public enum DatabaseCloseOutcome: String, Sendable {
    case closed
    case alreadyClosed = "already_closed"
    case failed
}
