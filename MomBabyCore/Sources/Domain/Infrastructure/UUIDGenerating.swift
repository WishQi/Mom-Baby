import Foundation

/// Creates identifiers without coupling domain code to global randomness.
public protocol UUIDGenerating: Sendable {
    func makeUUID() -> UUID
}
