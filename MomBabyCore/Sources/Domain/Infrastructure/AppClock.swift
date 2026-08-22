import Foundation

/// Supplies wall-clock time to domain and infrastructure code.
///
/// Production and test implementations live at their respective composition
/// boundaries so callers never need to read the system clock directly.
public protocol AppClock: Sendable {
    var now: Date { get }
}
