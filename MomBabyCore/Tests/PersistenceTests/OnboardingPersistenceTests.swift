import Foundation
import GRDB
import Testing

import Domain
@testable import Persistence

@Suite("Onboarding persistence")
struct OnboardingPersistenceTests {
    @Test("IOS-ONB-EMPTY-001 empty migrated vault is incomplete")
    func emptyVaultIsIncomplete() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())

        #expect(try await coordinator.loadOnboarding() == .incomplete)
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-ONB-001 onboarding aggregate round trips atomically")
    func completeAggregateRoundTrips() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest()

        let created = try await coordinator.completeOnboarding(request)
        let loaded = try await coordinator.loadOnboarding()

        #expect(loaded == .complete(created))
        #expect(created.baby.nickname == "小满")
        #expect(created.enabledModules == [.nursing, .bottle, .diaper, .sleep])
        #expect(created.homeModules == [.nursing, .bottle, .diaper, .sleep])
        #expect(created.lactatingProfileID != nil)
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-ONB-DISK-001 sentinel and test identity survive a disk reopen")
    func temporaryDiskSecurityMaterialSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomBabyOnboardingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dependencies = PersistenceDependencies(
            clock: OnboardingFixedClock(now: fixedNow),
            uuid: SequenceUUIDGenerator(),
            logger: DisabledPrivacyLogger()
        )
        let first = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: dependencies
        )
        _ = try readyReport(await first.bootstrap())
        let created = try await first.completeOnboarding(validRequest())
        #expect(await first.close() == .closed)

        let sentinelURL = directory.appendingPathComponent("RestoreSentinel")
        #expect(try Data(contentsOf: sentinelURL).count == 32)
        #expect(
            try sentinelURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup == true
        )

        let second = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: PersistenceDependencies(
                clock: OnboardingFixedClock(now: fixedNow),
                uuid: SequenceUUIDGenerator(),
                logger: DisabledPrivacyLogger()
            )
        )
        _ = try readyReport(await second.bootstrap())
        #expect(try await second.loadOnboarding() == .complete(created))
        #expect(await second.close() == .closed)
    }

    @Test("IOS-ONB-RESTORE-001 missing sentinel is never silently replaced")
    func missingSentinelFailsClosed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomBabyOnboardingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dependencies = PersistenceDependencies(
            clock: OnboardingFixedClock(now: fixedNow),
            uuid: SequenceUUIDGenerator(),
            logger: DisabledPrivacyLogger()
        )
        let first = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: dependencies
        )
        _ = try readyReport(await first.bootstrap())
        _ = try await first.completeOnboarding(validRequest())
        #expect(await first.close() == .closed)

        let sentinelURL = directory.appendingPathComponent("RestoreSentinel")
        try FileManager.default.removeItem(at: sentinelURL)
        let second = DatabaseBootstrapCoordinator.temporary(
            directory: directory,
            dependencies: dependencies
        )
        _ = try readyReport(await second.bootstrap())
        do {
            _ = try await second.loadOnboarding()
            Issue.record("Expected missing restore sentinel to fail closed")
        } catch let error as OnboardingError {
            #expect(error == .restoreReviewRequired)
        }
        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))
        #expect(await second.close() == .closed)
    }

    @Test("IOS-ONB-SENTINEL-RACE-001 concurrent creation never overwrites winner")
    func concurrentSentinelCreationUsesOneWinner() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomBabyOnboardingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = try VaultLocator.prepareTemporaryDirectory(directory)

        let values = try await withThrowingTaskGroup(of: Data.self) { group in
            for marker in UInt8(1)...16 {
                group.addTask {
                    try VaultLocator.loadOrCreateRestoreSentinel(at: location) {
                        Data(repeating: marker, count: 32)
                    }
                }
            }
            var results: [Data] = []
            for try await result in group { results.append(result) }
            return results
        }

        #expect(Set(values).count == 1)
        #expect(try Data(contentsOf: location.restoreSentinelURL) == values[0])
    }

    @Test("IOS-ONB-UNSPECIFIED-001 does not invent a growth reference group")
    func unspecifiedGrowthGroupRoundTrips() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest(
            growthGroup: .unspecified,
            enabledModules: [.bottle, .growth],
            homeModules: [.bottle, .growth],
            adultConsent: nil
        )

        let snapshot = try await coordinator.completeOnboarding(request)

        #expect(snapshot.baby.growthReferenceGroup == .unspecified)
        #expect(snapshot.lactatingProfileID == nil)
        #expect(try await coordinator.loadOnboarding() == .complete(snapshot))
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-ONB-DATE-001 rejects a future local birth date")
    func futureBirthDateIsRejected() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest(birthLocalDate: "2024-08-31")

        await expectOnboardingError(.birthDateInFuture) {
            try await coordinator.completeOnboarding(request)
        }
        #expect(try await coordinator.loadOnboarding() == .incomplete)
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-MODULE-PREF-001 home modules are capped at four")
    func homeModuleLimitIsEnforced() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest(
            enabledModules: [.nursing, .pumping, .bottle, .diaper, .sleep],
            homeModules: [.nursing, .pumping, .bottle, .diaper, .sleep]
        )

        await expectOnboardingError(.invalidModuleSelection) {
            try await coordinator.completeOnboarding(request)
        }
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-CONSENT-ADULT-001 nursing and pumping need separate adult consent")
    func adultConsentIsRequiredForAdultModules() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest(adultConsent: nil)

        await expectOnboardingError(.missingAdultLactationConsent) {
            try await coordinator.completeOnboarding(request)
        }
        #expect(try await coordinator.loadOnboarding() == .incomplete)
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-CONSENT-GUARDIAN-001 repository requires guardian declaration")
    func guardianDeclarationIsRequired() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest(guardianDeclared: false)

        await expectOnboardingError(.guardianDeclarationRequired) {
            try await coordinator.completeOnboarding(request)
        }
        #expect(try await coordinator.loadOnboarding() == .incomplete)
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-ONB-IDEMP-001 repeated command returns its original result")
    func repeatedCommandIsIdempotentAndConflictsOnDifferentInput() async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())
        let request = validRequest()

        let first = try await coordinator.completeOnboarding(request)
        let second = try await coordinator.completeOnboarding(request)
        #expect(second == first)

        let conflicting = validRequest(nickname: "另一个昵称")
        await expectOnboardingError(.commandConflict) {
            try await coordinator.completeOnboarding(conflicting)
        }
        #expect(try await coordinator.loadOnboarding() == .complete(first))
        #expect(await coordinator.close() == .closed)
    }

    @Test("IOS-ONB-HALF-001 partial aggregate fails closed")
    func partialAggregateFailsClosed() async throws {
        let owner = try await migratedOnboardingOwner()
        try await owner.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_vault (
                        id, state, created_at_ms, updated_at_ms
                    ) VALUES (?, 'active', ?, ?)
                    """,
                arguments: [
                    "7c0ee7ef-fbf3-4377-8b88-c47efedff111",
                    fixedNowMilliseconds,
                    fixedNowMilliseconds,
                ]
            )
        }

        do {
            _ = try await owner.read { database in
                try OnboardingRepository.load(
                    database,
                    security: OnboardingSecurityMaterial(
                        deviceInstallationID: "45ee7bc9-c82f-48d1-b059-a01f1f6dc222",
                        restoreSentinelHash: String(repeating: "c", count: 64)
                    )
                )
            }
            Issue.record("Expected partial onboarding aggregate to fail closed")
        } catch let error as OnboardingError {
            #expect(error == .inconsistentState)
        }
        #expect(await owner.close() == .closed)
    }

    @Test("IOS-ONB-ATOMIC-001 failed aggregate write leaves every table empty")
    func failedAggregateWriteRollsBack() async throws {
        let owner = try await migratedOnboardingOwner()
        let validated = try OnboardingRequestValidator.validate(
            validRequest(),
            now: fixedNow
        )
        do {
            _ = try await owner.write { database in
                try OnboardingRepository.complete(
                    validated,
                    in: database,
                    nowMilliseconds: fixedNowMilliseconds,
                    security: OnboardingSecurityMaterial(
                        deviceInstallationID: "45ee7bc9-c82f-48d1-b059-a01f1f6dc222",
                        restoreSentinelHash: "not-a-sha256"
                    ),
                    uuid: SequenceUUIDGenerator()
                )
            }
            Issue.record("Expected the invalid installation hash to abort")
        } catch {
            // Expected: the device_installation CHECK aborts the writer
            // transaction after vault and actor inserts have executed.
        }

        let remainingRows = try await owner.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT
                      (SELECT COUNT(*) FROM local_vault) +
                      (SELECT COUNT(*) FROM local_actor) +
                      (SELECT COUNT(*) FROM device_installation) +
                      (SELECT COUNT(*) FROM baby_profile) +
                      (SELECT COUNT(*) FROM consent_record) +
                      (SELECT COUNT(*) FROM module_preference) +
                      (SELECT COUNT(*) FROM operation_ledger)
                    """
            )
        }
        #expect(remainingRows == 0)
        #expect(await owner.close() == .closed)
    }

    @Test(
        "IOS-ONB-VALIDATION-001 repository rejects malformed sensitive fields",
        arguments: [
            InvalidRequestCase.nickname,
            .date,
            .timeZone,
            .noticeHash,
            .scopeJSON,
            .policyVersion,
            .swappedAdultEvidence,
            .homePositions,
        ]
    )
    func invalidSensitiveFieldsAreRejected(testCase: InvalidRequestCase) async throws {
        let coordinator = makeCoordinator()
        _ = try readyReport(await coordinator.bootstrap())

        await expectOnboardingError(testCase.expectedError) {
            try await coordinator.completeOnboarding(testCase.request)
        }
        #expect(try await coordinator.loadOnboarding() == .incomplete)
        #expect(await coordinator.close() == .closed)
    }
}

enum InvalidRequestCase: String, Sendable, CustomTestStringConvertible {
    case nickname
    case date
    case timeZone
    case noticeHash
    case scopeJSON
    case policyVersion
    case swappedAdultEvidence
    case homePositions

    var testDescription: String { rawValue }

    var expectedError: OnboardingError {
        switch self {
        case .nickname: .invalidNickname
        case .date: .invalidBirthLocalDate
        case .timeZone: .invalidTimeZone
        case .noticeHash, .scopeJSON, .policyVersion, .swappedAdultEvidence:
            .invalidConsentEvidence
        case .homePositions: .invalidModuleSelection
        }
    }

    var request: CompleteOnboardingRequest {
        switch self {
        case .nickname:
            validRequest(nickname: " \n ")
        case .date:
            validRequest(birthLocalDate: "2024-02-30")
        case .timeZone:
            validRequest(homeTimeZone: "Not/A_Time_Zone")
        case .noticeHash:
            validRequest(
                childConsent: ConsentEvidence(
                    policyVersion: OnboardingConsentPolicy.child.policyVersion,
                    scopeJSON: OnboardingConsentPolicy.child.scopeJSON,
                    noticeSHA256: String(repeating: "A", count: 64)
                )
            )
        case .scopeJSON:
            validRequest(
                childConsent: ConsentEvidence(
                    policyVersion: OnboardingConsentPolicy.child.policyVersion,
                    scopeJSON: "not-json",
                    noticeSHA256: OnboardingConsentPolicy.child.noticeSHA256
                )
            )
        case .policyVersion:
            validRequest(
                childConsent: ConsentEvidence(
                    policyVersion: "untrusted-version",
                    scopeJSON: OnboardingConsentPolicy.child.scopeJSON,
                    noticeSHA256: OnboardingConsentPolicy.child.noticeSHA256
                )
            )
        case .swappedAdultEvidence:
            validRequest(
                adultConsent: ConsentEvidence(
                    policyVersion: OnboardingConsentPolicy.child.policyVersion,
                    scopeJSON: OnboardingConsentPolicy.child.scopeJSON,
                    noticeSHA256: OnboardingConsentPolicy.child.noticeSHA256
                )
            )
        case .homePositions:
            validRequest(
                enabledModules: [.bottle],
                homeModules: [.bottle, .bottle],
                adultConsent: nil
            )
        }
    }
}

private let fixedNow = Date(timeIntervalSince1970: 1_725_004_800)
private let fixedNowMilliseconds: Int64 = 1_725_004_800_000
private let commandID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

private func validRequest(
    guardianDeclared: Bool = true,
    nickname: String = "小满",
    birthLocalDate: String = "2024-08-20",
    growthGroup: GrowthReferenceGroup = .female,
    homeTimeZone: String = "Asia/Shanghai",
    enabledModules: [HomeModule] = [.nursing, .bottle, .diaper, .sleep],
    homeModules: [HomeModule] = [.nursing, .bottle, .diaper, .sleep],
    childConsent: ConsentEvidence = ConsentEvidence(
        policyVersion: OnboardingConsentPolicy.child.policyVersion,
        scopeJSON: OnboardingConsentPolicy.child.scopeJSON,
        noticeSHA256: OnboardingConsentPolicy.child.noticeSHA256
    ),
    adultConsent: ConsentEvidence? = ConsentEvidence(
        policyVersion: OnboardingConsentPolicy.adultLactation.policyVersion,
        scopeJSON: OnboardingConsentPolicy.adultLactation.scopeJSON,
        noticeSHA256: OnboardingConsentPolicy.adultLactation.noticeSHA256
    )
) -> CompleteOnboardingRequest {
    CompleteOnboardingRequest(
        commandID: commandID,
        guardianDeclared: guardianDeclared,
        nickname: nickname,
        birthLocalDate: birthLocalDate,
        growthReferenceGroup: growthGroup,
        homeTimeZone: homeTimeZone,
        enabledModules: enabledModules,
        homeModules: homeModules,
        childConsent: childConsent,
        adultLactationConsent: adultConsent
    )
}

private func makeCoordinator() -> DatabaseBootstrapCoordinator {
    DatabaseBootstrapCoordinator.inMemory(
        dependencies: PersistenceDependencies(
            clock: OnboardingFixedClock(now: fixedNow),
            uuid: SequenceUUIDGenerator(),
            logger: DisabledPrivacyLogger()
        )
    )
}

private func readyReport(
    _ outcome: DatabaseBootstrapOutcome
) throws -> DatabaseValidationReport {
    guard case .ready(let report) = outcome else {
        throw UnexpectedOnboardingBootstrapOutcome(outcome: outcome)
    }
    return report
}

private struct UnexpectedOnboardingBootstrapOutcome: Error {
    let outcome: DatabaseBootstrapOutcome
}

private struct OnboardingFixedClock: AppClock {
    let now: Date
}

private final class SequenceUUIDGenerator: UUIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue = 1

    func makeUUID() -> UUID {
        lock.withLock {
            defer { nextValue += 1 }
            return UUID(
                uuidString: String(
                    format: "00000000-0000-4000-8000-%012d",
                    nextValue
                )
            )!
        }
    }
}

private func expectOnboardingError(
    _ expected: OnboardingError,
    operation: () async throws -> OnboardingSnapshot
) async {
    do {
        _ = try await operation()
        Issue.record("Expected onboarding error: \(expected)")
    } catch let error as OnboardingError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func migratedOnboardingOwner() async throws -> DatabaseOwner {
    let owner = try DatabaseOwnerFactory.inMemory()
    try await owner.migrate(
        try AppDatabaseMigrator(
            installedAtMilliseconds: fixedNowMilliseconds
        ).migrator
    )
    return owner
}
