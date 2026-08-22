import GRDB

/// The single lifecycle owner of an application's GRDB writer.
///
/// Database connections and rows never cross this actor boundary. Internal
/// repository implementations can only return `Sendable` snapshots.
public actor DatabaseOwner {
    private enum Lifecycle {
        case open
        case closing
        case closed
        case failed
    }

    private let writer: any DatabaseWriter
    nonisolated let expectedJournalMode: String
    private var lifecycle = Lifecycle.open
    private var activeOperationCount = 0
    private var zeroOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeWaiters: [CheckedContinuation<DatabaseCloseOutcome, Never>] = []

    init(writer: any DatabaseWriter, expectedJournalMode: String) {
        self.writer = writer
        self.expectedJournalMode = expectedJournalMode
    }

    func read<Value: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        let writer = try beginOperation()
        do {
            let value = try await writer.read(body)
            finishOperation()
            return value
        } catch {
            finishOperation()
            throw error
        }
    }

    func write<Value: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        let writer = try beginOperation()
        do {
            let value = try await writer.write(body)
            finishOperation()
            return value
        } catch {
            finishOperation()
            throw error
        }
    }

    func writeWithoutTransaction<Value: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        let writer = try beginOperation()
        do {
            let value = try await writer.writeWithoutTransaction(body)
            finishOperation()
            return value
        } catch {
            finishOperation()
            throw error
        }
    }

    func migrate(_ migrator: DatabaseMigrator) async throws {
        let writer = try beginOperation()
        do {
            try await withCheckedThrowingContinuation { continuation in
                migrator.asyncMigrate(writer) { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            finishOperation()
        } catch {
            finishOperation()
            throw error
        }
    }

    public func close() async -> DatabaseCloseOutcome {
        switch lifecycle {
        case .closed:
            return .alreadyClosed
        case .failed:
            return .failed
        case .closing:
            return await withCheckedContinuation { continuation in
                closeWaiters.append(continuation)
            }
        case .open:
            lifecycle = .closing
        }

        if activeOperationCount > 0 {
            await withCheckedContinuation { continuation in
                zeroOperationWaiters.append(continuation)
            }
        }

        let outcome: DatabaseCloseOutcome
        do {
            try writer.close()
            lifecycle = .closed
            outcome = .closed
        } catch {
            lifecycle = .failed
            outcome = .failed
        }

        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
        return outcome
    }

    private func beginOperation() throws -> any DatabaseWriter {
        guard case .open = lifecycle else {
            throw DatabaseLifecycleError.unavailable
        }
        activeOperationCount += 1
        return writer
    }

    private func finishOperation() {
        precondition(activeOperationCount > 0)
        activeOperationCount -= 1
        guard activeOperationCount == 0 else { return }

        let waiters = zeroOperationWaiters
        zeroOperationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

enum DatabaseLifecycleError: Error, Sendable {
    case unavailable
}
