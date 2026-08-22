import CryptoKit
import Domain
import Foundation

struct OnboardingPolicyNotice: Identifiable, Sendable {
    let id: String
    let title: String
    let version: String
    let body: String
    let scopeJSON: String

    var evidence: ConsentEvidence {
        let digest = SHA256.hash(data: Data(body.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return ConsentEvidence(
            policyVersion: version,
            scopeJSON: scopeJSON,
            noticeSHA256: hash
        )
    }
}

enum OnboardingPolicyStore {
    static func childNotice(bundle: Bundle = .main) throws -> OnboardingPolicyNotice {
        try load(
            resource: "ChildPrivacyNotice.v1",
            title: "儿童个人信息处理说明",
            contract: OnboardingConsentPolicy.child,
            bundle: bundle
        )
    }

    static func adultLactationNotice(bundle: Bundle = .main) throws -> OnboardingPolicyNotice {
        try load(
            resource: "AdultLactationNotice.v1",
            title: "成人哺乳与吸奶信息处理说明",
            contract: OnboardingConsentPolicy.adultLactation,
            bundle: bundle
        )
    }

    private static func load(
        resource: String,
        title: String,
        contract: OnboardingConsentPolicy.Contract,
        bundle: Bundle
    ) throws -> OnboardingPolicyNotice {
        guard let url = bundle.url(forResource: resource, withExtension: "txt") else {
            throw OnboardingPolicyError.missingResource(resource)
        }
        let body = try String(contentsOf: url, encoding: .utf8)
        let notice = OnboardingPolicyNotice(
            id: resource,
            title: title,
            version: contract.policyVersion,
            body: body,
            scopeJSON: contract.scopeJSON
        )
        guard notice.evidence.noticeSHA256 == contract.noticeSHA256 else {
            throw OnboardingPolicyError.resourceDoesNotMatchContract(resource)
        }
        return notice
    }
}

enum OnboardingPolicyError: Error {
    case missingResource(String)
    case resourceDoesNotMatchContract(String)
}
