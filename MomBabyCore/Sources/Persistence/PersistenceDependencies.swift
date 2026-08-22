import Domain
import Foundation

/// Cross-cutting dependencies shared by future persistence implementations.
///
/// Keeping this bundle in the Persistence module makes its inward dependency on
/// Domain explicit without selecting a database implementation during T0-A.
public struct PersistenceDependencies: Sendable {
    public let clock: any AppClock
    public let uuid: any UUIDGenerating
    public let logger: any PrivacyLogger

    public init(
        clock: any AppClock,
        uuid: any UUIDGenerating,
        logger: any PrivacyLogger
    ) {
        self.clock = clock
        self.uuid = uuid
        self.logger = logger
    }

    /// Foundation-backed dependencies suitable for the live composition root.
    ///
    /// The logger defaults to an explicitly disabled implementation until the
    /// App target supplies its OSLog adapter.
    public static func system(
        logger: any PrivacyLogger = DisabledPrivacyLogger()
    ) -> PersistenceDependencies {
        PersistenceDependencies(
            clock: SystemAppClock(),
            uuid: SystemUUIDGenerator(),
            logger: logger
        )
    }
}

private struct SystemAppClock: AppClock {
    var now: Date { Date() }
}

private struct SystemUUIDGenerator: UUIDGenerating {
    func makeUUID() -> UUID {
        UUID()
    }
}
