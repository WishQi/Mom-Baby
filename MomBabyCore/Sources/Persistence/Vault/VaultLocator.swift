import Domain
import Darwin
import Foundation

struct VaultLocation: Sendable {
    let databaseURL: URL
    fileprivate let pendingActivation: PendingVaultActivation?

    fileprivate init(
        databaseURL: URL,
        pendingActivation: PendingVaultActivation? = nil
    ) {
        self.databaseURL = databaseURL
        self.pendingActivation = pendingActivation
    }

    var isProvisioning: Bool { pendingActivation != nil }

    var restoreSentinelURL: URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("RestoreSentinel")
    }
}

private struct PendingVaultActivation: Sendable {
    let vaultID: String
    let pointerURL: URL
    let markerURL: URL
}

enum VaultLocator {
    private static let rootDirectoryName = "MomBaby"
    private static let vaultsDirectoryName = "Vaults"
    private static let currentVaultFileName = "CurrentVault"
    private static let provisioningFileName = "ProvisioningVault"
    private static let databaseFileName = "store.sqlite"
    private static let restoreSentinelFileName = "RestoreSentinel"
    private static let expectedVaultEntries: Set<String> = [
        "staging",
        "trash",
        restoreSentinelFileName,
        databaseFileName,
        "\(databaseFileName)-wal",
        "\(databaseFileName)-shm",
    ]

    static func locateOrCreate(
        applicationSupportDirectory: URL,
        uuid: any UUIDGenerating
    ) throws -> VaultLocation {
        let rootURL = applicationSupportDirectory
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
        let rootType = try itemType(at: rootURL)
        let rootWasAbsent = rootType == nil

        switch rootType {
        case nil:
            try prepareDirectory(rootURL)
        case .typeDirectory:
            try protectAndExcludeFromBackup(rootURL)
        case .some:
            throw VaultLocationError.invalidPointer
        }

        let pointerURL = rootURL.appendingPathComponent(currentVaultFileName)
        let markerURL = rootURL.appendingPathComponent(provisioningFileName)
        let markerID = try provisioningVaultID(at: markerURL)

        switch try itemType(at: pointerURL) {
        case .typeRegular:
            try protectAndExcludeFromBackup(pointerURL)
            let pointer = try readStateFile(at: pointerURL)
            if pointer.hasPrefix("unavailable:") {
                let operationID = String(pointer.dropFirst("unavailable:".count))
                guard isCanonicalUUID(operationID) else {
                    throw VaultLocationError.invalidPointer
                }
                throw VaultLocationError.unavailablePointer
            }
            guard pointer.hasPrefix("active:") else {
                throw VaultLocationError.invalidPointer
            }
            let vaultID = String(pointer.dropFirst("active:".count))
            guard isCanonicalUUID(vaultID), markerID == nil || markerID == vaultID else {
                throw VaultLocationError.invalidPointer
            }
            return try locateActiveVault(
                rootURL: rootURL,
                vaultID: vaultID,
                pointerURL: pointerURL,
                markerURL: markerID == nil ? nil : markerURL
            )
        case .typeSymbolicLink, .some:
            throw VaultLocationError.invalidPointer
        case nil:
            if let markerID {
                return try resumeProvisioning(
                    rootURL: rootURL,
                    vaultID: markerID,
                    pointerURL: pointerURL,
                    markerURL: markerURL
                )
            }

            // A brand-new or wholly empty app root is the only state that can
            // prove there is no prior vault to hide. Any other missing pointer
            // fails closed instead of silently publishing a replacement vault.
            let entries = try directoryEntryNames(at: rootURL)
            guard rootWasAbsent || entries.isEmpty else {
                throw VaultLocationError.invalidPointer
            }
            let vaultID = uuid.makeUUID().uuidString.lowercased()
            guard isCanonicalUUID(vaultID) else {
                throw VaultLocationError.invalidPointer
            }
            try writeStateFile(
                "provisioning:\(vaultID)",
                to: markerURL,
                requireAbsent: true
            )
            return try resumeProvisioning(
                rootURL: rootURL,
                vaultID: vaultID,
                pointerURL: pointerURL,
                markerURL: markerURL
            )
        }
    }

    static func prepareTemporaryDirectory(_ directoryURL: URL) throws -> VaultLocation {
        try prepareDirectory(directoryURL)
        try prepareDirectory(directoryURL.appendingPathComponent("staging", isDirectory: true))
        try prepareDirectory(directoryURL.appendingPathComponent("trash", isDirectory: true))
        let databaseURL = directoryURL.appendingPathComponent(databaseFileName)
        try validateDatabaseArtifacts(
            databaseURL: databaseURL,
            databaseRequired: false,
            nonEmptyDatabaseRequired: false
        )
        try protectDatabaseArtifacts(databaseURL: databaseURL)
        return VaultLocation(databaseURL: databaseURL)
    }

    /// Publishes a provisioned vault only after migration and validation have
    /// succeeded. The marker makes an interrupted first install resumable,
    /// while the active pointer remains the single atomic visibility boundary.
    static func activateAfterValidation(_ location: VaultLocation) throws {
        guard let activation = location.pendingActivation else { return }
        guard try provisioningVaultID(at: activation.markerURL) == activation.vaultID else {
            throw VaultLocationError.invalidPointer
        }

        try validateDatabaseArtifacts(
            databaseURL: location.databaseURL,
            databaseRequired: true,
            nonEmptyDatabaseRequired: true
        )
        try protectDatabaseArtifacts(databaseURL: location.databaseURL)

        let expectedPointer = "active:\(activation.vaultID)"
        switch try itemType(at: activation.pointerURL) {
        case nil:
            try writeStateFile(
                expectedPointer,
                to: activation.pointerURL,
                requireAbsent: true
            )
        case .typeRegular:
            try protectAndExcludeFromBackup(activation.pointerURL)
            guard try readStateFile(at: activation.pointerURL) == expectedPointer else {
                throw VaultLocationError.invalidPointer
            }
        case .some:
            throw VaultLocationError.invalidPointer
        }

        do {
            try FileManager.default.removeItem(at: activation.markerURL)
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }

    static func protectDatabaseArtifacts(databaseURL: URL) throws {
        try validateDatabaseArtifacts(
            databaseURL: databaseURL,
            databaseRequired: false,
            nonEmptyDatabaseRequired: false
        )
        for artifactURL in databaseArtifactURLs(for: databaseURL)
        where try itemType(at: artifactURL) != nil {
            try protectAndExcludeFromBackup(artifactURL)
        }
    }

    /// Reads the 256-bit, per-vault restore sentinel without ever replacing a
    /// missing or malformed value. Existing onboarding data must use this
    /// fail-closed path so a restored database cannot be silently relabeled as
    /// a fresh installation.
    static func loadRestoreSentinel(at location: VaultLocation) throws -> Data? {
        let url = location.restoreSentinelURL
        switch try itemType(at: url) {
        case nil:
            return nil
        case .typeRegular:
            try protectAndExcludeFromBackup(url)
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw VaultLocationError.protectionFailed
            }
            guard data.count == 32 else {
                throw VaultLocationError.invalidPointer
            }
            return data
        case .some:
            throw VaultLocationError.invalidPointer
        }
    }

    /// Creates the restore sentinel only for a provably pre-onboarding vault.
    /// The caller supplies cryptographically secure entropy and verifies that
    /// the database has no onboarding state before invoking this method.
    static func loadOrCreateRestoreSentinel(
        at location: VaultLocation,
        entropy: @Sendable () throws -> Data
    ) throws -> Data {
        if let existing = try loadRestoreSentinel(at: location) {
            return existing
        }

        let value = try entropy()
        guard value.count == 32 else {
            throw VaultLocationError.protectionFailed
        }
        do {
            guard try createFileExclusively(
                at: location.restoreSentinelURL,
                contents: value
            ) else {
                guard let winner = try loadRestoreSentinel(at: location) else {
                    throw VaultLocationError.protectionFailed
                }
                return winner
            }
            try protectAndExcludeFromBackup(location.restoreSentinelURL)
        } catch let error as VaultLocationError {
            throw error
        } catch {
            throw VaultLocationError.protectionFailed
        }
        guard try loadRestoreSentinel(at: location) == value else {
            throw VaultLocationError.protectionFailed
        }
        return value
    }

    /// Returns false only when another creator already won the path. A failed
    /// partial write is unlinked, while an existing winner is never replaced.
    private static func createFileExclusively(
        at url: URL,
        contents: Data
    ) throws -> Bool {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw VaultLocationError.protectionFailed }
            let descriptor = open(
                path,
                O_WRONLY | O_CREAT | O_EXCL,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else {
                if errno == EEXIST { return false }
                throw VaultLocationError.protectionFailed
            }

            var succeeded = false
            defer {
                _ = close(descriptor)
                if !succeeded { _ = unlink(path) }
            }
            let wroteAllBytes = contents.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return contents.isEmpty
                }
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        bytes.count - offset
                    )
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
            guard wroteAllBytes, fsync(descriptor) == 0 else {
                throw VaultLocationError.protectionFailed
            }
            succeeded = true
            return true
        }
    }

    /// Applies the same disk policy to a test-only temporary identity sidecar.
    /// Live storage keeps this identity in ThisDeviceOnly Keychain instead.
    static func protectAuxiliaryFile(at url: URL) throws {
        guard try itemType(at: url) == .typeRegular else {
            throw VaultLocationError.invalidPointer
        }
        try protectAndExcludeFromBackup(url)
    }

    private static func locateActiveVault(
        rootURL: URL,
        vaultID: String,
        pointerURL: URL,
        markerURL: URL?
    ) throws -> VaultLocation {
        let vaultsURL = rootURL
            .appendingPathComponent(vaultsDirectoryName, isDirectory: true)
        try requireDirectory(vaultsURL)
        let vaultURL = try checkedVaultURL(vaultID: vaultID, vaultsURL: vaultsURL)
        try requireDirectory(vaultURL)
        try requireDirectory(vaultURL.appendingPathComponent("staging", isDirectory: true))
        try requireDirectory(vaultURL.appendingPathComponent("trash", isDirectory: true))

        let databaseURL = vaultURL.appendingPathComponent(databaseFileName)
        try validateDatabaseArtifacts(
            databaseURL: databaseURL,
            databaseRequired: true,
            nonEmptyDatabaseRequired: true
        )
        // Repair and read back protection before DatabaseCompatibility or GRDB
        // is allowed to inspect/open any existing SQLite artifact.
        try protectDatabaseArtifacts(databaseURL: databaseURL)

        let activation = markerURL.map {
            PendingVaultActivation(
                vaultID: vaultID,
                pointerURL: pointerURL,
                markerURL: $0
            )
        }
        return VaultLocation(
            databaseURL: databaseURL,
            pendingActivation: activation
        )
    }

    private static func resumeProvisioning(
        rootURL: URL,
        vaultID: String,
        pointerURL: URL,
        markerURL: URL
    ) throws -> VaultLocation {
        let rootEntries = try directoryEntryNames(at: rootURL)
        guard rootEntries.isSubset(of: [provisioningFileName, vaultsDirectoryName]) else {
            throw VaultLocationError.invalidPointer
        }

        let vaultsURL = rootURL
            .appendingPathComponent(vaultsDirectoryName, isDirectory: true)
        try prepareDirectory(vaultsURL)
        let existingVaultIDs = try directoryEntryNames(at: vaultsURL)
        guard existingVaultIDs.isEmpty || existingVaultIDs == [vaultID] else {
            throw VaultLocationError.invalidPointer
        }

        let vaultURL = try checkedVaultURL(vaultID: vaultID, vaultsURL: vaultsURL)
        try prepareDirectory(vaultURL)
        let vaultEntries = try directoryEntryNames(at: vaultURL)
        guard vaultEntries.isSubset(of: expectedVaultEntries) else {
            throw VaultLocationError.invalidPointer
        }
        try prepareDirectory(vaultURL.appendingPathComponent("staging", isDirectory: true))
        try prepareDirectory(vaultURL.appendingPathComponent("trash", isDirectory: true))

        let databaseURL = vaultURL.appendingPathComponent(databaseFileName)
        if try itemType(at: databaseURL) == nil {
            guard FileManager.default.createFile(
                atPath: databaseURL.path,
                contents: Data()
            ) else {
                throw VaultLocationError.protectionFailed
            }
        }
        try validateDatabaseArtifacts(
            databaseURL: databaseURL,
            databaseRequired: true,
            nonEmptyDatabaseRequired: false
        )
        try protectDatabaseArtifacts(databaseURL: databaseURL)

        return VaultLocation(
            databaseURL: databaseURL,
            pendingActivation: PendingVaultActivation(
                vaultID: vaultID,
                pointerURL: pointerURL,
                markerURL: markerURL
            )
        )
    }

    private static func checkedVaultURL(vaultID: String, vaultsURL: URL) throws -> URL {
        let vaultURL = vaultsURL.appendingPathComponent(vaultID, isDirectory: true)
        guard vaultURL.deletingLastPathComponent().standardizedFileURL ==
                vaultsURL.standardizedFileURL,
              vaultURL.resolvingSymlinksInPath().deletingLastPathComponent() ==
                vaultsURL.resolvingSymlinksInPath() else {
            throw VaultLocationError.invalidPointer
        }
        return vaultURL
    }

    private static func prepareDirectory(_ directoryURL: URL) throws {
        switch try itemType(at: directoryURL) {
        case .typeSymbolicLink:
            throw VaultLocationError.invalidPointer
        case .typeDirectory:
            break
        case .some:
            throw VaultLocationError.invalidPointer
        case nil:
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw VaultLocationError.protectionFailed
            }
        }
        try protectAndExcludeFromBackup(directoryURL)
    }

    private static func requireDirectory(_ directoryURL: URL) throws {
        guard try itemType(at: directoryURL) == .typeDirectory else {
            throw VaultLocationError.invalidPointer
        }
        try protectAndExcludeFromBackup(directoryURL)
    }

    private static func protectAndExcludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)

        let readBack = try mutableURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard readBack.isExcludedFromBackup == true else {
            throw VaultLocationError.protectionFailed
        }

#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protectionReadback = VaultFileProtectionReadback(
            attribute: attributes[.protectionKey]
        )
#if targetEnvironment(simulator)
        let permitsMissingProtectionReadback = true
#else
        let permitsMissingProtectionReadback = false
#endif
        guard protectionReadback.isAcceptable(
            permitsMissingValue: permitsMissingProtectionReadback
        ) else {
            throw VaultLocationError.protectionFailed
        }
#endif
    }

    private static func provisioningVaultID(at markerURL: URL) throws -> String? {
        switch try itemType(at: markerURL) {
        case nil:
            return nil
        case .typeRegular:
            try protectAndExcludeFromBackup(markerURL)
            let marker = try readStateFile(at: markerURL)
            guard marker.hasPrefix("provisioning:") else {
                throw VaultLocationError.invalidPointer
            }
            let vaultID = String(marker.dropFirst("provisioning:".count))
            guard isCanonicalUUID(vaultID) else {
                throw VaultLocationError.invalidPointer
            }
            return vaultID
        case .some:
            throw VaultLocationError.invalidPointer
        }
    }

    private static func writeStateFile(
        _ value: String,
        to url: URL,
        requireAbsent: Bool
    ) throws {
        if requireAbsent, try itemType(at: url) != nil {
            throw VaultLocationError.invalidPointer
        }
        do {
            try Data(value.utf8).write(to: url, options: .atomic)
            guard try itemType(at: url) == .typeRegular else {
                throw VaultLocationError.invalidPointer
            }
            try protectAndExcludeFromBackup(url)
            guard try readStateFile(at: url) == value else {
                throw VaultLocationError.protectionFailed
            }
        } catch let error as VaultLocationError {
            throw error
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }

    private static func readStateFile(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func validateDatabaseArtifacts(
        databaseURL: URL,
        databaseRequired: Bool,
        nonEmptyDatabaseRequired: Bool
    ) throws {
        let parentURL = databaseURL.deletingLastPathComponent().resolvingSymlinksInPath()
        for (index, artifactURL) in databaseArtifactURLs(for: databaseURL).enumerated() {
            guard let type = try itemType(at: artifactURL) else {
                if index == 0, databaseRequired {
                    throw VaultLocationError.invalidPointer
                }
                continue
            }
            guard type == .typeRegular,
                  artifactURL.resolvingSymlinksInPath().deletingLastPathComponent() == parentURL else {
                throw VaultLocationError.invalidPointer
            }
            if index == 0, nonEmptyDatabaseRequired,
               try fileSize(at: artifactURL) == 0 {
                throw VaultLocationError.invalidPointer
            }
        }
    }

    private static func databaseArtifactURLs(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
    }

    private static func directoryEntryNames(at directoryURL: URL) throws -> Set<String> {
        do {
            return Set(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }

    private static func itemType(at url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw VaultLocationError.protectionFailed
        }
    }
}

enum VaultFileProtectionReadback: Equatable {
    case missing
    case protection(FileProtectionType)
    case invalid

    init(attribute: Any?) {
        guard let attribute else {
            self = .missing
            return
        }
        if let protection = attribute as? FileProtectionType {
            self = .protection(protection)
        } else if let rawValue = attribute as? String {
            self = .protection(FileProtectionType(rawValue: rawValue))
        } else {
            self = .invalid
        }
    }

    /// CoreSimulator accepts the protection attribute write but does not expose
    /// a value when it is read back. A missing value may therefore be accepted
    /// only by the simulator caller. Any explicit weaker class still fails.
    func isAcceptable(permitsMissingValue: Bool) -> Bool {
        switch self {
        case .protection(.complete):
            true
        case .missing:
            permitsMissingValue
        case .protection, .invalid:
            false
        }
    }
}

enum VaultLocationError: Error, Sendable {
    case invalidPointer
    case unavailablePointer
    case protectionFailed
}
