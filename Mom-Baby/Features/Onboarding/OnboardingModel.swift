import Domain
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    typealias CompleteOperation = @MainActor (CompleteOnboardingRequest) async throws -> OnboardingSnapshot

    enum Step: Int, CaseIterable {
        case welcome
        case consent
        case profile
        case modules
    }

    private(set) var step: Step = .welcome
    var guardianDeclared = false
    var childConsentGranted = false
    var nickname = "" {
        didSet { invalidateSubmissionCommandIfChanged(oldValue != nickname) }
    }
    var birthDate: Date? {
        didSet { invalidateSubmissionCommandIfChanged(oldValue != birthDate) }
    }
    var growthReferenceGroup: GrowthReferenceGroup = .unspecified {
        didSet {
            invalidateSubmissionCommandIfChanged(oldValue != growthReferenceGroup)
        }
    }
    private(set) var selectedModules: [HomeModule] = [] {
        didSet { invalidateSubmissionCommandIfChanged(oldValue != selectedModules) }
    }
    private(set) var adultLactationConsentGranted = false {
        didSet {
            invalidateSubmissionCommandIfChanged(oldValue != adultLactationConsentGranted)
        }
    }
    private(set) var isSubmitting = false
    var errorMessage: String?
    var presentedNotice: OnboardingPolicyNotice?

    @ObservationIgnored private let completeOperation: CompleteOperation
    @ObservationIgnored private(set) var childNotice: OnboardingPolicyNotice?
    @ObservationIgnored private(set) var adultNotice: OnboardingPolicyNotice?
    @ObservationIgnored private(set) var policyLoadFailure: String?
    /// The whole request, not only its command ID, is retained after an
    /// ambiguous failure. A retry must be byte-for-byte equivalent even if the
    /// device time zone changes while the error alert is visible.
    @ObservationIgnored private var pendingSubmission: CompleteOnboardingRequest?

    init(completeOperation: @escaping CompleteOperation) {
        self.completeOperation = completeOperation
        do {
            childNotice = try OnboardingPolicyStore.childNotice()
            adultNotice = try OnboardingPolicyStore.adultLactationNotice()
        } catch {
            policyLoadFailure = "隐私说明资源暂不可用，请重新安装开发版本后再试。"
        }
    }

    var canContinueFromConsent: Bool {
        guardianDeclared && childConsentGranted && childNotice != nil
    }

    var normalizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canContinueFromProfile: Bool {
        guard !normalizedNickname.isEmpty,
              normalizedNickname.utf8.count <= 512,
              let birthDate else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.startOfDay(for: birthDate) <= calendar.startOfDay(for: Date())
    }

    var requiresAdultLactationConsent: Bool {
        selectedModules.contains(.nursing) || selectedModules.contains(.pumping)
    }

    var canComplete: Bool {
        guard !selectedModules.isEmpty,
              childNotice != nil else { return false }
        if requiresAdultLactationConsent {
            return adultLactationConsentGranted && adultNotice != nil
        }
        return true
    }

    func moveForward() {
        guard !isSubmitting else { return }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func moveBack() {
        guard !isSubmitting else { return }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func toggle(_ module: HomeModule) {
        guard !isSubmitting else { return }
        if selectedModules.contains(module) {
            selectedModules.removeAll { $0 == module }
        } else {
            selectedModules.append(module)
        }
    }

    func useDefaultModules() {
        guard !isSubmitting else { return }
        selectedModules = HomeModule.defaultHomeModules
    }

    func toggleAdultLactationConsent() {
        guard !isSubmitting else { return }
        adultLactationConsentGranted.toggle()
    }

    func showChildNotice() {
        presentedNotice = childNotice
    }

    func showAdultNotice() {
        presentedNotice = adultNotice
    }

    func complete() async {
        guard !isSubmitting,
              canContinueFromProfile,
              canComplete,
              let birthDate,
              let childNotice else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let userSelectedModules = HomeModule.onboardingChoices.filter(selectedModules.contains)
        let enabledModules = userSelectedModules + [.growth, .moments]
        let homeModules = Array(userSelectedModules.prefix(4))
        let adultEvidence = requiresAdultLactationConsent
            ? adultNotice?.evidence
            : nil

        let request: CompleteOnboardingRequest
        if let pendingSubmission {
            request = pendingSubmission
        } else {
            request = CompleteOnboardingRequest(
                commandID: UUID().uuidString.lowercased(),
                guardianDeclared: guardianDeclared,
                nickname: normalizedNickname,
                birthLocalDate: Self.localDateString(from: birthDate),
                growthReferenceGroup: growthReferenceGroup,
                homeTimeZone: TimeZone.current.identifier,
                enabledModules: enabledModules,
                homeModules: homeModules,
                childConsent: childNotice.evidence,
                adultLactationConsent: adultEvidence
            )
            pendingSubmission = request
        }

        do {
            _ = try await completeOperation(request)
            pendingSubmission = nil
        } catch {
            errorMessage = "资料没有保存。请保持设备解锁后重试，Mom-Baby 不会保留半套建档资料。"
        }
    }

    private static func localDateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func invalidateSubmissionCommandIfChanged(_ didChange: Bool) {
        guard didChange else { return }
        pendingSubmission = nil
    }
}
