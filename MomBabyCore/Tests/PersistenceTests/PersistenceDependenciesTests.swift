import Foundation
import Testing

import Domain
@testable import Persistence

@Suite("Persistence module boundary")
struct PersistenceDependenciesTests {
    @Test("Persistence depends on injected Domain services")
    func dependenciesPreserveInjectedServices() {
        let expectedDate = Date(timeIntervalSince1970: 1_725_004_800)
        let expectedUUID = UUID(uuidString: "24a5ddaa-5ba7-4e58-a076-ec54dca91803")!
        let dependencies = PersistenceDependencies(
            clock: FixedClock(now: expectedDate),
            uuid: FixedUUIDGenerator(uuid: expectedUUID),
            logger: DisabledPrivacyLogger()
        )

        #expect(dependencies.clock.now == expectedDate)
        #expect(dependencies.uuid.makeUUID() == expectedUUID)
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
