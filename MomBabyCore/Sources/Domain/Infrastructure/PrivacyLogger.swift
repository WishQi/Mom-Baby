/// Severity levels supported by the privacy-safe logging boundary.
public enum PrivacyLogLevel: String, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

/// Coarse categories that are safe to expose in local diagnostics.
public enum PrivacyLogCategory: String, CaseIterable, Sendable {
    case application
    case domain
    case persistence
    case mediaProcessing = "media_processing"
}

/// A log event whose message must be a compile-time literal.
///
/// Dynamic user content is deliberately absent from this envelope. Structured,
/// allow-listed diagnostic values can be added as dedicated types when needed.
public struct PrivacyLogEvent: Sendable {
    public let level: PrivacyLogLevel
    public let category: PrivacyLogCategory
    public let message: StaticString

    public init(
        level: PrivacyLogLevel,
        category: PrivacyLogCategory,
        message: StaticString
    ) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// The only logging surface available to Core modules.
public protocol PrivacyLogger: Sendable {
    func log(_ event: PrivacyLogEvent)
}

/// An explicit disabled logger for previews and focused tests.
public struct DisabledPrivacyLogger: PrivacyLogger {
    public init() {}

    public func log(_ event: PrivacyLogEvent) {}
}
