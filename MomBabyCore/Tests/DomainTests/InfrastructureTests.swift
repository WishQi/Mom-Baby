import Foundation
import Testing

@testable import Domain

@Suite("Domain infrastructure boundaries")
struct InfrastructureTests {
    @Test("AppClock can provide deterministic time")
    func clockIsInjectable() {
        let expected = Date(timeIntervalSince1970: 1_725_004_800)
        let clock: any AppClock = FixedClock(now: expected)

        #expect(clock.now == expected)
    }

    @Test("UUIDGenerating can provide deterministic identifiers")
    func uuidGeneratorIsInjectable() {
        let expected = UUID(uuidString: "1e850558-561a-4cd6-941c-5ecf46de4bc8")!
        let generator: any UUIDGenerating = FixedUUIDGenerator(uuid: expected)

        #expect(generator.makeUUID() == expected)
    }

    @Test("Privacy events contain only a static message envelope")
    func privacyEventUsesStaticMessage() {
        let event = PrivacyLogEvent(
            level: .error,
            category: .persistence,
            message: "migration_failed"
        )

        #expect(event.level == .error)
        #expect(event.category == .persistence)
        #expect(event.message.description == "migration_failed")
    }

    @Test("Logging can be explicitly disabled")
    func disabledLoggerAcceptsSafeEvents() {
        let logger: any PrivacyLogger = DisabledPrivacyLogger()

        logger.log(
            PrivacyLogEvent(
                level: .debug,
                category: .domain,
                message: "test_event"
            )
        )
    }
}

private struct FixedClock: AppClock {
    let now: Date
}

private struct FixedUUIDGenerator: UUIDGenerating {
    let uuid: UUID

    func makeUUID() -> UUID {
        uuid
    }
}
