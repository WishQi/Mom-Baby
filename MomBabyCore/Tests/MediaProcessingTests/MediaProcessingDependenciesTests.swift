import Foundation
import Testing

import Domain
@testable import MediaProcessing

@Suite("Media processing module boundary")
struct MediaProcessingDependenciesTests {
    @Test("Media processing depends on injected Domain services")
    func dependenciesPreserveInjectedServices() {
        let expectedDate = Date(timeIntervalSince1970: 1_725_004_800)
        let dependencies = MediaProcessingDependencies(
            clock: FixedClock(now: expectedDate),
            logger: DisabledPrivacyLogger()
        )

        #expect(dependencies.clock.now == expectedDate)
    }
}

private struct FixedClock: AppClock {
    let now: Date
}
