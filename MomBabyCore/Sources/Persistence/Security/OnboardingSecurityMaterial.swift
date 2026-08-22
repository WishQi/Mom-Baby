import CryptoKit
import Domain
import Foundation
import Security

struct OnboardingSecurityMaterial: Sendable, Equatable {
    let deviceInstallationID: String
    let restoreSentinelHash: String
}

enum OnboardingSecurityStore {
    private static let keychainService = "com.maoqi.Mom-Baby.device-identity.v1"
    private static let keychainAccount = "local-device"
    private static let temporaryIdentityFileName = "TestDeviceIdentity"

    static func loadExistingLive(
        location: VaultLocation
    ) throws -> OnboardingSecurityMaterial? {
        guard let deviceID = try loadKeychainDeviceID(),
              let sentinel = try VaultLocator.loadRestoreSentinel(at: location) else {
            return nil
        }
        return material(deviceID: deviceID, sentinel: sentinel)
    }

    static func loadOrCreateLive(
        location: VaultLocation,
        uuid: any UUIDGenerating
    ) throws -> OnboardingSecurityMaterial {
        let deviceID = try loadOrCreateKeychainDeviceID(uuid: uuid)
        let sentinel = try VaultLocator.loadOrCreateRestoreSentinel(
            at: location,
            entropy: secureRandomSentinel
        )
        return material(deviceID: deviceID, sentinel: sentinel)
    }

    static func loadExistingTemporary(
        location: VaultLocation
    ) throws -> OnboardingSecurityMaterial? {
        guard let deviceID = try loadTemporaryDeviceID(location: location),
              let sentinel = try VaultLocator.loadRestoreSentinel(at: location) else {
            return nil
        }
        return material(deviceID: deviceID, sentinel: sentinel)
    }

    static func loadOrCreateTemporary(
        location: VaultLocation,
        uuid: any UUIDGenerating
    ) throws -> OnboardingSecurityMaterial {
        let deviceID = try loadOrCreateTemporaryDeviceID(
            location: location,
            uuid: uuid
        )
        let sentinel = try VaultLocator.loadOrCreateRestoreSentinel(
            at: location,
            entropy: secureRandomSentinel
        )
        return material(deviceID: deviceID, sentinel: sentinel)
    }

    static func makeEphemeral(
        uuid: any UUIDGenerating
    ) throws -> OnboardingSecurityMaterial {
        let deviceID = canonicalUUID(uuid.makeUUID())
        let sentinel = try secureRandomSentinel()
        return material(deviceID: deviceID, sentinel: sentinel)
    }

    private static func material(
        deviceID: String,
        sentinel: Data
    ) -> OnboardingSecurityMaterial {
        OnboardingSecurityMaterial(
            deviceInstallationID: deviceID,
            restoreSentinelHash: SHA256.hash(data: sentinel).hexString
        )
    }

    private static func secureRandomSentinel() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OnboardingSecurityError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func loadKeychainDeviceID() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrSynchronizable: false,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
            kSecReturnAttributes: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let attributes = result as? [CFString: Any],
                  let data = attributes[kSecValueData] as? Data,
                  let value = String(data: data, encoding: .utf8),
                  (attributes[kSecAttrAccessible] as? String) ==
                    (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
                  (attributes[kSecAttrSynchronizable] as? Bool) == false,
                  isCanonicalUUID(value) else {
                throw OnboardingSecurityError.invalidDeviceIdentity
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw OnboardingSecurityError.keychain(status)
        }
    }

    private static func loadOrCreateKeychainDeviceID(
        uuid: any UUIDGenerating
    ) throws -> String {
        if let existing = try loadKeychainDeviceID() {
            return existing
        }

        let value = canonicalUUID(uuid.makeUUID())
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrSynchronizable: false,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: Data(value.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try loadKeychainDeviceID() {
            return existing
        }
        guard status == errSecSuccess else {
            throw OnboardingSecurityError.keychain(status)
        }
        guard try loadKeychainDeviceID() == value else {
            throw OnboardingSecurityError.invalidDeviceIdentity
        }
        return value
    }

    private static func temporaryIdentityURL(location: VaultLocation) -> URL {
        location.databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(temporaryIdentityFileName)
    }

    private static func loadTemporaryDeviceID(
        location: VaultLocation
    ) throws -> String? {
        let url = temporaryIdentityURL(location: location)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try VaultLocator.protectAuxiliaryFile(at: url)
        let value = try String(contentsOf: url, encoding: .utf8)
        guard isCanonicalUUID(value) else {
            throw OnboardingSecurityError.invalidDeviceIdentity
        }
        return value
    }

    private static func loadOrCreateTemporaryDeviceID(
        location: VaultLocation,
        uuid: any UUIDGenerating
    ) throws -> String {
        if let existing = try loadTemporaryDeviceID(location: location) {
            return existing
        }
        let value = canonicalUUID(uuid.makeUUID())
        let url = temporaryIdentityURL(location: location)
        try Data(value.utf8).write(to: url, options: .atomic)
        try VaultLocator.protectAuxiliaryFile(at: url)
        guard try loadTemporaryDeviceID(location: location) == value else {
            throw OnboardingSecurityError.invalidDeviceIdentity
        }
        return value
    }

    private static func canonicalUUID(_ uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }
}

enum OnboardingSecurityError: Error, Sendable, Equatable {
    case randomGenerationFailed
    case invalidDeviceIdentity
    case keychain(OSStatus)
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
