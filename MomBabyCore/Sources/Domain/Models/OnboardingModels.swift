import Foundation

public enum GrowthReferenceGroup: String, CaseIterable, Sendable, Codable, Hashable {
    case male
    case female
    case unspecified
}

public enum HomeModule: String, CaseIterable, Sendable, Codable, Hashable {
    case nursing
    case pumping
    case bottle
    case diaper
    case sleep
    case growth
    case moments
    case supplies
}

public struct ConsentEvidence: Sendable, Equatable, Codable, Hashable {
    public let policyVersion: String
    public let scopeJSON: String
    public let noticeSHA256: String

    public init(
        policyVersion: String,
        scopeJSON: String,
        noticeSHA256: String
    ) {
        self.policyVersion = policyVersion
        self.scopeJSON = scopeJSON
        self.noticeSHA256 = noticeSHA256
    }
}

/// The exact, versioned notices shipped by this binary. Persistence accepts
/// consent only when the evidence matches one of these subject-specific
/// contracts; a syntactically valid arbitrary hash is not consent evidence.
public enum OnboardingConsentPolicy {
    public struct Contract: Sendable, Equatable, Hashable {
        public let policyVersion: String
        public let scopeJSON: String
        public let noticeSHA256: String

        public init(
            policyVersion: String,
            scopeJSON: String,
            noticeSHA256: String
        ) {
            self.policyVersion = policyVersion
            self.scopeJSON = scopeJSON
            self.noticeSHA256 = noticeSHA256
        }
    }

    public static let child = Contract(
        policyVersion: "2026.08-local-1",
        scopeJSON: #"{"categories":["baby_profile","care_records","growth","moments"],"storage":"local_only"}"#,
        noticeSHA256: "65f057cdc8982e5de704d404232b8297129cc1ff297bf2fabad217926b44f981"
    )

    public static let adultLactation = Contract(
        policyVersion: "2026.08-local-1",
        scopeJSON: #"{"categories":["nursing_side_detail","pumping_records"],"storage":"local_only"}"#,
        noticeSHA256: "9b4ba7a60dd8373092c41bc67a116ba18176759abf3a14b48d2938c5d9e6503d"
    )
}

public struct CompleteOnboardingRequest: Sendable, Equatable {
    /// Stable identifier generated once when the user starts the final save.
    /// Retrying the same save must reuse this value.
    public let commandID: String
    public let guardianDeclared: Bool
    public let nickname: String
    public let birthLocalDate: String
    public let growthReferenceGroup: GrowthReferenceGroup
    public let homeTimeZone: String
    public let enabledModules: [HomeModule]
    public let homeModules: [HomeModule]
    public let childConsent: ConsentEvidence
    public let adultLactationConsent: ConsentEvidence?

    public init(
        commandID: String,
        guardianDeclared: Bool,
        nickname: String,
        birthLocalDate: String,
        growthReferenceGroup: GrowthReferenceGroup,
        homeTimeZone: String,
        enabledModules: [HomeModule],
        homeModules: [HomeModule],
        childConsent: ConsentEvidence,
        adultLactationConsent: ConsentEvidence?
    ) {
        self.commandID = commandID
        self.guardianDeclared = guardianDeclared
        self.nickname = nickname
        self.birthLocalDate = birthLocalDate
        self.growthReferenceGroup = growthReferenceGroup
        self.homeTimeZone = homeTimeZone
        self.enabledModules = enabledModules
        self.homeModules = homeModules
        self.childConsent = childConsent
        self.adultLactationConsent = adultLactationConsent
    }
}

public struct BabyProfileSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let nickname: String
    public let birthLocalDate: String
    public let growthReferenceGroup: GrowthReferenceGroup
    public let homeTimeZone: String

    public init(
        id: String,
        nickname: String,
        birthLocalDate: String,
        growthReferenceGroup: GrowthReferenceGroup,
        homeTimeZone: String
    ) {
        self.id = id
        self.nickname = nickname
        self.birthLocalDate = birthLocalDate
        self.growthReferenceGroup = growthReferenceGroup
        self.homeTimeZone = homeTimeZone
    }
}

public struct OnboardingSnapshot: Sendable, Equatable {
    public let localVaultID: String
    public let localActorID: String
    public let baby: BabyProfileSnapshot
    public let lactatingProfileID: String?
    public let enabledModules: [HomeModule]
    public let homeModules: [HomeModule]

    public init(
        localVaultID: String,
        localActorID: String,
        baby: BabyProfileSnapshot,
        lactatingProfileID: String?,
        enabledModules: [HomeModule],
        homeModules: [HomeModule]
    ) {
        self.localVaultID = localVaultID
        self.localActorID = localActorID
        self.baby = baby
        self.lactatingProfileID = lactatingProfileID
        self.enabledModules = enabledModules
        self.homeModules = homeModules
    }
}

public enum OnboardingLoadState: Sendable, Equatable {
    case incomplete
    case complete(OnboardingSnapshot)
}

/// Fail-closed errors returned by the onboarding persistence boundary.
public enum OnboardingError: Error, Sendable, Equatable {
    case unavailable
    case invalidCommandID
    case guardianDeclarationRequired
    case invalidNickname
    case invalidBirthLocalDate
    case birthDateInFuture
    case invalidTimeZone
    case invalidModuleSelection
    case invalidConsentEvidence
    case missingAdultLactationConsent
    case unexpectedAdultLactationConsent
    case commandConflict
    case alreadyComplete
    case inconsistentState
    /// Existing database state is missing its non-restorable device identity
    /// or excluded restore sentinel. Recovery must not mint replacements.
    case restoreReviewRequired
    case securityMaterialUnavailable
}
