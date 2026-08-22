import Domain

/// Cross-cutting dependencies shared by future media workers.
///
/// UIKit and PhotosUI adapters intentionally remain outside this package.
public struct MediaProcessingDependencies: Sendable {
    public let clock: any AppClock
    public let logger: any PrivacyLogger

    public init(
        clock: any AppClock,
        logger: any PrivacyLogger
    ) {
        self.clock = clock
        self.logger = logger
    }
}
