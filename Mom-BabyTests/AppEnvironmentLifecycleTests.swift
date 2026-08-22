import Domain
import Persistence
import XCTest
@testable import Mom_Baby

final class AppEnvironmentLifecycleTests: XCTestCase {
    @MainActor
    func testRepeatedPreparationStartsOnlyOneBootstrapAttempt() async {
        let attempts = InvocationCounter()
        let environment = makeEnvironment(
            bootstrap: { _, progress in
                _ = await attempts.increment()
                await progress(.locatingVault)
                return .ready(Self.validationReport)
            }
        )

        environment.prepareForUse()
        environment.prepareForUse()

        await expectEventually { environment.bootstrapState == .ready }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testColdStartResamplesProtectedDataBeforeFirstBootstrap() async {
        let availability = ProtectedDataAvailability(false)
        let attempts = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .waitingForProtectedData,
            isProtectedDataAvailable: { availability.value },
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            }
        )

        availability.value = true
        environment.prepareForUse()

        await expectEventually { environment.bootstrapState == .ready }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testDidBecomeActiveRecoversWhenProtectedDataNotificationWasMissed() async {
        let availability = ProtectedDataAvailability(false)
        let attempts = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .waitingForProtectedData,
            isProtectedDataAvailable: { availability.value },
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            }
        )
        environment.prepareForUse()

        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(environment.bootstrapState, .waitingForProtectedData)

        availability.value = true
        environment.applicationDidBecomeActive()

        await expectEventually { environment.bootstrapState == .ready }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testDidBecomeActiveBeforePreparationQueuesOnlyOneBootstrapAttempt() async {
        let availability = ProtectedDataAvailability(false)
        let attempts = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .waitingForProtectedData,
            isProtectedDataAvailable: { availability.value },
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            }
        )

        availability.value = true
        environment.applicationDidBecomeActive()
        // Give the active reconciliation task a turn so its retry is already
        // buffered when the long-lived preparation consumer starts.
        await Task.yield()
        environment.prepareForUse()

        await expectEventually { environment.bootstrapState == .ready }
        for _ in 0..<10 {
            await Task.yield()
        }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testDidBecomeActiveCannotOverrideProtectedDataWillGraceWindow() async {
        let attempts = InvocationCounter()
        let suspensions = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .ready,
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            },
            suspend: {
                _ = await suspensions.increment()
                return .alreadyClosed
            }
        )
        environment.prepareForUse()

        // The fake UIKit flag remains true, matching the grace window after
        // willBecomeUnavailable. App-active must not treat that as an unlock.
        environment.protectedDataWillBecomeUnavailable()
        environment.applicationDidBecomeActive()
        await expectEventually { await suspensions.current() == 1 }
        for _ in 0..<10 {
            await Task.yield()
        }

        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 0)
        XCTAssertEqual(environment.bootstrapState, .waitingForProtectedData)
    }

    @MainActor
    func testRetryAndProtectedDataDidCoalesceAcrossSuspensionBarrier() async {
        let availability = ProtectedDataAvailability(false)
        let attempts = InvocationCounter()
        let suspensions = InvocationCounter()
        let suspensionGate = AsyncGate()
        let environment = makeEnvironment(
            bootstrapState: .ready,
            isProtectedDataAvailable: { availability.value },
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            },
            suspend: {
                _ = await suspensions.increment()
                await suspensionGate.wait()
                return .closed
            }
        )
        environment.prepareForUse()

        environment.protectedDataWillBecomeUnavailable()
        await expectEventually { await suspensions.current() == 1 }
        environment.retryBootstrap()
        availability.value = true
        environment.protectedDataDidBecomeAvailable()
        await suspensionGate.open()

        await expectEventually { environment.bootstrapState == .ready }
        for _ in 0..<10 {
            await Task.yield()
        }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testBootstrapOutlivesCancellationOfStartingViewTask() async {
        let attempts = InvocationCounter()
        let bootstrapGate = AsyncGate()
        let environment = makeEnvironment(
            bootstrap: { _, progress in
                _ = await attempts.increment()
                await progress(.migratingSchema)
                await bootstrapGate.wait()
                return .ready(Self.validationReport)
            }
        )

        let viewTask = Task { @MainActor in
            environment.prepareForUse()
            try? await Task.sleep(for: .seconds(5))
        }

        await expectEventually { await attempts.current() == 1 }
        viewTask.cancel()
        await viewTask.value
        await bootstrapGate.open()

        await expectEventually { environment.bootstrapState == .ready }
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testRepeatedStartAndRetryCommandsRemainSingleFlight() async {
        let attempts = InvocationCounter()
        let environment = makeEnvironment(
            bootstrap: { _, progress in
                let attempt = await attempts.increment()
                await progress(.validatingHeader)
                return attempt == 1
                    ? .protectionBlocked
                    : .ready(Self.validationReport)
            }
        )

        environment.prepareForUse()
        environment.prepareForUse()
        await expectEventually { environment.bootstrapState == .protectionBlocked }

        environment.retryBootstrap()
        environment.retryBootstrap()
        await expectEventually { environment.bootstrapState == .ready }

        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 2)
    }

    @MainActor
    func testFailedProtectedDataSuspensionFailsClosedAndBlocksRetry() async {
        let attempts = InvocationCounter()
        let suspensions = InvocationCounter()
        let environment = makeEnvironment(
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            },
            suspend: {
                _ = await suspensions.increment()
                return .failed
            }
        )

        environment.prepareForUse()
        await expectEventually { environment.bootstrapState == .ready }

        environment.protectedDataWillBecomeUnavailable()
        await expectEventually { environment.bootstrapState == .recoveryRequired }
        XCTAssertFalse(environment.canRetryBootstrap)

        environment.retryBootstrap()
        environment.protectedDataDidBecomeAvailable()
        for _ in 0..<10 {
            await Task.yield()
        }

        let attemptCount = await attempts.current()
        let suspensionCount = await suspensions.current()
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(suspensionCount, 1)
        XCTAssertEqual(environment.bootstrapState, .recoveryRequired)
    }

    @MainActor
    func testRapidRelockInvalidatesQueuedRetryFromPriorProtectionEpoch() async {
        let attempts = InvocationCounter()
        let suspensions = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .ready,
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            },
            suspend: {
                _ = await suspensions.increment()
                return .alreadyClosed
            }
        )
        environment.prepareForUse()

        // Keep the client's instantaneous availability reading true to model
        // UIKit's grace window. The notification epoch must still be decisive.
        environment.protectedDataWillBecomeUnavailable()
        await expectEventually { await suspensions.current() == 1 }
        environment.protectedDataDidBecomeAvailable()
        environment.retryBootstrap()
        environment.protectedDataWillBecomeUnavailable()

        for _ in 0..<25 {
            await Task.yield()
        }
        let attemptsWhileRelocked = await attempts.current()
        XCTAssertEqual(attemptsWhileRelocked, 0)
        XCTAssertEqual(environment.bootstrapState, .waitingForProtectedData)

        environment.protectedDataDidBecomeAvailable()
        await expectEventually { environment.bootstrapState == .ready }
        let finalAttemptCount = await attempts.current()
        let finalSuspensionCount = await suspensions.current()
        XCTAssertEqual(finalAttemptCount, 1)
        XCTAssertEqual(finalSuspensionCount, 2)
    }

    @MainActor
    func testQueuedRetryCannotBootstrapAfterProtectedDataWillNotification() async {
        let attempts = InvocationCounter()
        let suspensions = InvocationCounter()
        let environment = makeEnvironment(
            bootstrapState: .protectionBlocked,
            bootstrap: { _, _ in
                _ = await attempts.increment()
                return .ready(Self.validationReport)
            },
            suspend: {
                _ = await suspensions.increment()
                return .alreadyClosed
            }
        )
        environment.prepareForUse()

        environment.retryBootstrap()
        environment.protectedDataWillBecomeUnavailable()
        await expectEventually { await suspensions.current() == 1 }
        for _ in 0..<25 {
            await Task.yield()
        }

        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 0)
        XCTAssertEqual(environment.bootstrapState, .waitingForProtectedData)
    }

    @MainActor
    func testIOSONB001ReadyDatabaseWithoutProfileShowsOnboarding() async {
        let environment = makeEnvironment(
            bootstrap: { _, _ in .ready(Self.validationReport) },
            loadOnboarding: { .incomplete }
        )

        environment.prepareForUse()

        await expectEventually {
            environment.bootstrapState == .ready &&
                environment.experienceState == .onboarding
        }
    }

    @MainActor
    func testIOSONB001ReadyDatabaseWithProfileShowsTodayExperience() async {
        let snapshot = Self.onboardingSnapshot
        let environment = makeEnvironment(
            bootstrap: { _, _ in .ready(Self.validationReport) },
            loadOnboarding: { .complete(snapshot) }
        )

        environment.prepareForUse()

        await expectEventually {
            environment.bootstrapState == .ready &&
                environment.experienceState == .ready(snapshot)
        }
    }

    @MainActor
    func testIOSONB001CompletedOnboardingPublishesCommittedSnapshot() async throws {
        let snapshot = Self.onboardingSnapshot
        let environment = makeEnvironment(
            bootstrapState: .ready,
            experienceState: .onboarding,
            bootstrap: { _, _ in .ready(Self.validationReport) },
            completeOnboarding: { _ in snapshot }
        )

        let result = try await environment.completeOnboarding(
            Self.completeOnboardingRequest
        )

        XCTAssertEqual(result, snapshot)
        XCTAssertEqual(environment.experienceState, .ready(snapshot))
    }

    @MainActor
    func testProtectedDataRevocationClearsSensitiveExperienceSnapshot() {
        let environment = makeEnvironment(
            bootstrapState: .ready,
            experienceState: .ready(Self.onboardingSnapshot),
            bootstrap: { _, _ in .ready(Self.validationReport) }
        )

        environment.protectedDataWillBecomeUnavailable()

        XCTAssertEqual(environment.bootstrapState, .waitingForProtectedData)
        XCTAssertEqual(environment.experienceState, .loading)
    }

    @MainActor
    private func makeEnvironment(
        bootstrapState: AppBootstrapState = .locatingVault,
        experienceState: AppExperienceState = .loading,
        isProtectedDataAvailable: @escaping @MainActor @Sendable () -> Bool = {
            true
        },
        bootstrap: @escaping AppBootstrapClient.BootstrapOperation,
        suspend: @escaping @Sendable () async -> DatabaseCloseOutcome = {
            .alreadyClosed
        },
        loadOnboarding: @escaping AppBootstrapClient.LoadOnboardingOperation = {
            .incomplete
        },
        completeOnboarding: @escaping AppBootstrapClient.CompleteOnboardingOperation = { _ in
            throw AppBootstrapClientError.databaseUnavailable
        }
    ) -> AppEnvironment {
        AppEnvironment(
            router: AppRouter(),
            bootstrapClient: AppBootstrapClient(
                isProtectedDataAvailable: isProtectedDataAvailable,
                bootstrap: bootstrap,
                suspendForProtectedData: suspend,
                loadOnboarding: loadOnboarding,
                completeOnboarding: completeOnboarding
            ),
            bootstrapState: bootstrapState,
            experienceState: experienceState
        )
    }

    @MainActor
    private func expectEventually(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<250 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTFail("Condition did not become true", file: file, line: line)
    }

    private static let validationReport = DatabaseValidationReport(
        applicationID: SchemaContract.applicationID,
        schemaVersion: 1,
        schemaFingerprint: "test",
        quickCheck: "ok",
        integrityCheck: "ok",
        foreignKeyViolationCount: 0,
        tableCount: 44,
        indexCount: 36,
        triggerCount: 86,
        pragmas: DatabasePragmaReport(
            foreignKeysEnabled: true,
            journalMode: "wal",
            synchronousLevel: 2,
            secureDeleteEnabled: true,
            temporaryStore: 2,
            busyTimeoutMilliseconds: 5_000
        )
    )

    private static let onboardingSnapshot = OnboardingSnapshot(
        localVaultID: "3dc7f0c9-7801-4994-af81-f6b875757c66",
        localActorID: "09cb1050-cf33-45ca-bc09-15bbd8aec177",
        baby: BabyProfileSnapshot(
            id: "32946591-192d-45ab-ab65-b7ccf5339b11",
            nickname: "小满",
            birthLocalDate: "2026-06-09",
            growthReferenceGroup: .unspecified,
            homeTimeZone: "Asia/Shanghai"
        ),
        lactatingProfileID: nil,
        enabledModules: [.bottle, .diaper, .sleep, .growth, .moments],
        homeModules: [.bottle, .diaper, .sleep]
    )

    private static let completeOnboardingRequest = CompleteOnboardingRequest(
        commandID: "b9416a35-170a-492c-8782-c2f6dfbf839e",
        guardianDeclared: true,
        nickname: "小满",
        birthLocalDate: "2026-06-09",
        growthReferenceGroup: .unspecified,
        homeTimeZone: "Asia/Shanghai",
        enabledModules: [.bottle, .diaper, .sleep, .growth, .moments],
        homeModules: [.bottle, .diaper, .sleep],
        childConsent: ConsentEvidence(
            policyVersion: "test-v1",
            scopeJSON: #"{"storage":"local_only"}"#,
            noticeSHA256: String(repeating: "a", count: 64)
        ),
        adultLactationConsent: nil
    )
}

@MainActor
private final class ProtectedDataAvailability {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

private actor InvocationCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }

    func current() -> Int {
        value
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}
