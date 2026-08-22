import Domain
import XCTest
@testable import Mom_Baby

@MainActor
final class OnboardingModelTests: XCTestCase {
    func testIOSConsent001BundledNoticesMatchPersistedPolicyContracts() throws {
        let child = try OnboardingPolicyStore.childNotice()
        let adult = try OnboardingPolicyStore.adultLactationNotice()

        XCTAssertEqual(child.evidence.policyVersion, OnboardingConsentPolicy.child.policyVersion)
        XCTAssertEqual(child.evidence.scopeJSON, OnboardingConsentPolicy.child.scopeJSON)
        XCTAssertEqual(child.evidence.noticeSHA256, OnboardingConsentPolicy.child.noticeSHA256)
        XCTAssertEqual(adult.evidence.policyVersion, OnboardingConsentPolicy.adultLactation.policyVersion)
        XCTAssertEqual(adult.evidence.scopeJSON, OnboardingConsentPolicy.adultLactation.scopeJSON)
        XCTAssertEqual(adult.evidence.noticeSHA256, OnboardingConsentPolicy.adultLactation.noticeSHA256)
    }

    func testIOSConsent001RequiresGuardianAndSeparateChildConsent() {
        let model = OnboardingModel { _ in Self.snapshot }

        XCTAssertFalse(model.canContinueFromConsent)
        model.guardianDeclared = true
        XCTAssertFalse(model.canContinueFromConsent)
        model.childConsentGranted = true
        XCTAssertTrue(model.canContinueFromConsent)
    }

    func testIOSModulePref001DefaultModulesRequireAdultLactationConsent() {
        let model = OnboardingModel { _ in Self.snapshot }
        configureRequiredProfile(on: model)

        model.useDefaultModules()

        XCTAssertEqual(model.selectedModules, [.nursing, .bottle, .diaper, .sleep])
        XCTAssertTrue(model.requiresAdultLactationConsent)
        XCTAssertFalse(model.canComplete)
        model.toggleAdultLactationConsent()
        XCTAssertTrue(model.canComplete)
    }

    func testIOSONB001SubmissionFreezesEditsAndAmbiguousRetryReusesEntireRequest() async {
        var requests: [CompleteOnboardingRequest] = []
        let submissionGate = OnboardingSubmissionGate()
        let model = OnboardingModel { request in
            requests.append(request)
            if requests.count == 1 {
                await submissionGate.wait()
                throw TestFailure.ambiguous
            }
            return Self.snapshot
        }
        configureRequiredProfile(on: model)
        model.toggle(.bottle)
        model.toggle(.diaper)
        model.toggle(.sleep)
        model.moveForward()
        model.moveForward()
        model.moveForward()

        let firstSubmission = Task { @MainActor in
            await model.complete()
        }
        for _ in 0..<100 {
            if model.isSubmitting, !requests.isEmpty { break }
            await Task.yield()
        }

        let visibleModules = model.selectedModules
        model.toggle(.nursing)
        model.useDefaultModules()
        model.toggleAdultLactationConsent()
        model.moveBack()

        XCTAssertTrue(model.isSubmitting)
        XCTAssertEqual(model.selectedModules, visibleModules)
        XCTAssertFalse(model.adultLactationConsentGranted)
        XCTAssertEqual(model.step, .modules)

        await submissionGate.open()
        await firstSubmission.value
        XCTAssertNotNil(model.errorMessage)
        await model.complete()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first, requests.last)
        XCTAssertNil(model.errorMessage)
    }

    private func configureRequiredProfile(on model: OnboardingModel) {
        model.guardianDeclared = true
        model.childConsentGranted = true
        model.nickname = "小满"
        model.birthDate = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private static let snapshot = OnboardingSnapshot(
        localVaultID: "3dc7f0c9-7801-4994-af81-f6b875757c66",
        localActorID: "09cb1050-cf33-45ca-bc09-15bbd8aec177",
        baby: BabyProfileSnapshot(
            id: "32946591-192d-45ab-ab65-b7ccf5339b11",
            nickname: "小满",
            birthLocalDate: "2023-11-15",
            growthReferenceGroup: .unspecified,
            homeTimeZone: "Asia/Shanghai"
        ),
        lactatingProfileID: nil,
        enabledModules: [.bottle, .diaper, .sleep, .growth, .moments],
        homeModules: [.bottle, .diaper, .sleep]
    )

    private enum TestFailure: Error {
        case ambiguous
    }
}

private actor OnboardingSubmissionGate {
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
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
