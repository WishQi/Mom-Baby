import CryptoKit
import Domain
import Foundation

struct ValidatedOnboardingRequest: Sendable {
    let commandID: String
    let nickname: String
    let birthLocalDate: String
    let growthReferenceGroup: GrowthReferenceGroup
    let homeTimeZone: String
    let enabledModules: [HomeModule]
    let homeModules: [HomeModule]
    let childConsent: ValidatedConsentEvidence
    let adultLactationConsent: ValidatedConsentEvidence?
    let inputSHA256: String
}

struct ValidatedConsentEvidence: Sendable, Codable {
    let policyVersion: String
    let scopeJSON: String
    let noticeSHA256: String
}

enum OnboardingRequestValidator {
    static func validate(
        _ request: CompleteOnboardingRequest,
        now: Date
    ) throws -> ValidatedOnboardingRequest {
        guard isCanonicalUUID(request.commandID) else {
            throw OnboardingError.invalidCommandID
        }
        guard request.guardianDeclared else {
            throw OnboardingError.guardianDeclarationRequired
        }

        let nickname = request.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty,
              nickname.utf8.count <= 512,
              !nickname.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw OnboardingError.invalidNickname
        }

        guard request.homeTimeZone.utf8.count <= 64,
              let timeZone = TimeZone(identifier: request.homeTimeZone) else {
            throw OnboardingError.invalidTimeZone
        }
        try validateBirthDate(
            request.birthLocalDate,
            latestAllowedDate: now,
            timeZone: timeZone
        )

        let enabledSet = Set(request.enabledModules)
        let homeSet = Set(request.homeModules)
        guard enabledSet.count == request.enabledModules.count,
              homeSet.count == request.homeModules.count,
              request.homeModules.count <= 4,
              homeSet.isSubset(of: enabledSet) else {
            throw OnboardingError.invalidModuleSelection
        }

        let childConsent = try validateConsent(
            request.childConsent,
            expected: OnboardingConsentPolicy.child
        )
        let needsAdultConsent = enabledSet.contains(.nursing) || enabledSet.contains(.pumping)
        let adultConsent: ValidatedConsentEvidence?
        switch (needsAdultConsent, request.adultLactationConsent) {
        case (true, .none):
            throw OnboardingError.missingAdultLactationConsent
        case (false, .some):
            throw OnboardingError.unexpectedAdultLactationConsent
        case (true, .some(let evidence)):
            adultConsent = try validateConsent(
                evidence,
                expected: OnboardingConsentPolicy.adultLactation
            )
        case (false, .none):
            adultConsent = nil
        }

        let enabledModules = HomeModule.allCases.filter(enabledSet.contains)
        let payload = CanonicalOnboardingPayload(
            guardianDeclared: true,
            nickname: nickname,
            birthLocalDate: request.birthLocalDate,
            growthReferenceGroup: request.growthReferenceGroup.rawValue,
            homeTimeZone: request.homeTimeZone,
            enabledModules: enabledModules.map(\.rawValue),
            homeModules: request.homeModules.map(\.rawValue),
            childConsent: childConsent,
            adultLactationConsent: adultConsent
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let inputData = try encoder.encode(payload)

        return ValidatedOnboardingRequest(
            commandID: request.commandID,
            nickname: nickname,
            birthLocalDate: request.birthLocalDate,
            growthReferenceGroup: request.growthReferenceGroup,
            homeTimeZone: request.homeTimeZone,
            enabledModules: enabledModules,
            homeModules: request.homeModules,
            childConsent: childConsent,
            adultLactationConsent: adultConsent,
            inputSHA256: SHA256.hash(data: inputData).hexString
        )
    }

    static func validateStoredBaby(
        nickname: String,
        birthLocalDate: String,
        homeTimeZone: String,
        createdAtMilliseconds: Int64
    ) throws {
        let normalizedNickname = nickname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedNickname == nickname,
              !nickname.isEmpty,
              nickname.utf8.count <= 512,
              !nickname.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ),
              homeTimeZone.utf8.count <= 64,
              createdAtMilliseconds > 0,
              let timeZone = TimeZone(identifier: homeTimeZone) else {
            throw OnboardingError.inconsistentState
        }
        do {
            try validateBirthDate(
                birthLocalDate,
                latestAllowedDate: Date(
                    timeIntervalSince1970: Double(createdAtMilliseconds) / 1_000
                ),
                timeZone: timeZone
            )
        } catch {
            throw OnboardingError.inconsistentState
        }
    }

    private static func validateBirthDate(
        _ value: String,
        latestAllowedDate: Date?,
        timeZone: TimeZone
    ) throws {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw OnboardingError.invalidBirthLocalDate
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            throw OnboardingError.invalidBirthLocalDate
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw OnboardingError.invalidBirthLocalDate
        }
        if let latestAllowedDate,
           date > calendar.startOfDay(for: latestAllowedDate) {
            throw OnboardingError.birthDateInFuture
        }
    }

    private static func validateConsent(
        _ evidence: ConsentEvidence,
        expected: OnboardingConsentPolicy.Contract
    ) throws -> ValidatedConsentEvidence {
        let policyVersion = evidence.policyVersion
        guard policyVersion == expected.policyVersion,
              policyVersion.utf8.count <= 128,
              evidence.scopeJSON.utf8.count <= 16_384,
              isLowercaseSHA256(evidence.noticeSHA256),
              let scopeData = evidence.scopeJSON.data(using: .utf8) else {
            throw OnboardingError.invalidConsentEvidence
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: scopeData)
        } catch {
            throw OnboardingError.invalidConsentEvidence
        }
        guard JSONSerialization.isValidJSONObject(object),
              let canonicalScope = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let scopeJSON = String(data: canonicalScope, encoding: .utf8) else {
            throw OnboardingError.invalidConsentEvidence
        }
        guard scopeJSON == expected.scopeJSON,
              evidence.noticeSHA256 == expected.noticeSHA256 else {
            throw OnboardingError.invalidConsentEvidence
        }
        return ValidatedConsentEvidence(
            policyVersion: policyVersion,
            scopeJSON: scopeJSON,
            noticeSHA256: evidence.noticeSHA256
        )
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

private struct CanonicalOnboardingPayload: Codable {
    let guardianDeclared: Bool
    let nickname: String
    let birthLocalDate: String
    let growthReferenceGroup: String
    let homeTimeZone: String
    let enabledModules: [String]
    let homeModules: [String]
    let childConsent: ValidatedConsentEvidence
    let adultLactationConsent: ValidatedConsentEvidence?
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
