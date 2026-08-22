import Domain
import Foundation
import GRDB

enum OnboardingRepository {
    private static let operationType = "complete_onboarding"

    static func hasAnyState(_ database: Database) throws -> Bool {
        let sql = """
            SELECT
              (SELECT COUNT(*) FROM local_vault) +
              (SELECT COUNT(*) FROM local_actor) +
              (SELECT COUNT(*) FROM device_installation) +
              (SELECT COUNT(*) FROM baby_profile) +
              (SELECT COUNT(*) FROM lactating_profile) +
              (SELECT COUNT(*) FROM consent_record) +
              (SELECT COUNT(*) FROM module_preference) +
              (SELECT COUNT(*) FROM operation_ledger
                 WHERE operation_type = ?) AS state_count
            """
        return try Int.fetchOne(database, sql: sql, arguments: [operationType]) != 0
    }

    static func load(
        _ database: Database,
        security: OnboardingSecurityMaterial?
    ) throws -> OnboardingLoadState {
        guard try hasAnyState(database) else { return .incomplete }
        guard let security else {
            throw OnboardingError.securityMaterialUnavailable
        }
        do {
            return .complete(
                try loadCompleteSnapshot(
                    database,
                    security: security
                )
            )
        } catch let error as OnboardingError {
            throw error
        } catch {
            throw OnboardingError.inconsistentState
        }
    }

    static func complete(
        _ request: ValidatedOnboardingRequest,
        in database: Database,
        nowMilliseconds: Int64,
        security: OnboardingSecurityMaterial,
        uuid: any UUIDGenerating
    ) throws -> OnboardingSnapshot {
        if let command = try existingCommand(
            request.commandID,
            database: database
        ) {
            guard command.inputSHA256 == request.inputSHA256 else {
                throw OnboardingError.commandConflict
            }
            guard command.operationType == operationType,
                  command.state == "succeeded" else {
                throw OnboardingError.inconsistentState
            }
            let snapshot = try loadCompleteSnapshot(
                database,
                security: security
            )
            guard command.resultType == "baby_profile",
                  command.resultID == snapshot.baby.id,
                  command.resultRevision == 1,
                  snapshotMatchesValidatedInput(snapshot, request: request) else {
                throw OnboardingError.inconsistentState
            }
            return snapshot
        }

        if try hasAnyState(database) {
            do {
                _ = try loadCompleteSnapshot(
                    database,
                    security: security
                )
                throw OnboardingError.alreadyComplete
            } catch OnboardingError.alreadyComplete {
                throw OnboardingError.alreadyComplete
            } catch {
                throw OnboardingError.inconsistentState
            }
        }

        var usedIDs: Set<String> = [request.commandID, security.deviceInstallationID]
        let vaultID = try makeUniqueID(uuid: uuid, used: &usedIDs)
        let actorID = try makeUniqueID(uuid: uuid, used: &usedIDs)
        let babyID = try makeUniqueID(uuid: uuid, used: &usedIDs)
        let childConsentID = try makeUniqueID(uuid: uuid, used: &usedIDs)
        let lactatingProfileID = try request.adultLactationConsent.map { _ in
            try makeUniqueID(uuid: uuid, used: &usedIDs)
        }
        let adultConsentID = try request.adultLactationConsent.map { _ in
            try makeUniqueID(uuid: uuid, used: &usedIDs)
        }

        try database.execute(
            sql: """
                INSERT INTO local_vault (
                    id, state, data_revision, created_at_ms, updated_at_ms
                ) VALUES (?, 'active', 1, ?, ?)
                """,
            arguments: [vaultID, nowMilliseconds, nowMilliseconds]
        )
        try database.execute(
            sql: """
                INSERT INTO local_actor (
                    id, local_vault_id, guardian_declared,
                    created_at_ms, updated_at_ms
                ) VALUES (?, ?, 1, ?, ?)
                """,
            arguments: [actorID, vaultID, nowMilliseconds, nowMilliseconds]
        )
        try database.execute(
            sql: """
                INSERT INTO device_installation (
                    id, local_vault_id, state, schema_version,
                    media_layout_version, schema_fingerprint,
                    restore_sentinel_hash, backup_policy_generation,
                    created_at_ms
                ) VALUES (?, ?, 'active', ?, ?, ?, ?, 1, ?)
                """,
            arguments: [
                security.deviceInstallationID,
                vaultID,
                SchemaContract.currentVersion,
                SchemaContract.mediaLayoutVersion,
                SchemaContract.expectedFingerprint,
                security.restoreSentinelHash,
                nowMilliseconds,
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO operation_ledger (
                    command_id, local_vault_id, operation_type,
                    input_sha256, state, created_at_ms
                ) VALUES (?, ?, ?, ?, 'pending', ?)
                """,
            arguments: [
                request.commandID,
                vaultID,
                operationType,
                request.inputSHA256,
                nowMilliseconds,
            ]
        )

        try insertChildConsent(
            request.childConsent,
            id: childConsentID,
            vaultID: vaultID,
            babyID: babyID,
            actorID: actorID,
            grantedAtMilliseconds: nowMilliseconds,
            database: database
        )
        try database.execute(
            sql: """
                INSERT INTO baby_profile (
                    id, local_vault_id, nickname, birth_local_date,
                    growth_group, home_time_zone, current_consent_id,
                    created_at_ms, updated_at_ms,
                    created_by_actor_id, updated_by_actor_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                babyID,
                vaultID,
                request.nickname,
                request.birthLocalDate,
                request.growthReferenceGroup.rawValue,
                request.homeTimeZone,
                childConsentID,
                nowMilliseconds,
                nowMilliseconds,
                actorID,
                actorID,
            ]
        )

        if let adultEvidence = request.adultLactationConsent,
           let lactatingProfileID,
           let adultConsentID {
            try insertAdultConsent(
                adultEvidence,
                id: adultConsentID,
                vaultID: vaultID,
                profileID: lactatingProfileID,
                actorID: actorID,
                grantedAtMilliseconds: nowMilliseconds,
                database: database
            )
            try database.execute(
                sql: """
                    INSERT INTO lactating_profile (
                        id, local_vault_id, owner_actor_id, home_time_zone,
                        current_consent_id, created_at_ms, updated_at_ms,
                        created_by_actor_id, updated_by_actor_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    lactatingProfileID,
                    vaultID,
                    actorID,
                    request.homeTimeZone,
                    adultConsentID,
                    nowMilliseconds,
                    nowMilliseconds,
                    actorID,
                    actorID,
                ]
            )
        }

        let enabledSet = Set(request.enabledModules)
        let positions = Dictionary(
            uniqueKeysWithValues: request.homeModules.enumerated().map {
                ($0.element, $0.offset + 1)
            }
        )
        for module in HomeModule.allCases {
            try database.execute(
                sql: """
                    INSERT INTO module_preference (
                        local_vault_id, module_type, is_enabled,
                        home_position, updated_at_ms
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: StatementArguments([
                    vaultID,
                    module.rawValue,
                    enabledSet.contains(module) ? 1 : 0,
                    positions[module],
                    nowMilliseconds,
                ] as [(any DatabaseValueConvertible)?])
            )
        }

        try database.execute(
            sql: """
                UPDATE operation_ledger
                SET state = 'succeeded',
                    result_type = 'baby_profile',
                    result_id = ?,
                    result_revision = 1,
                    completed_at_ms = ?
                WHERE command_id = ? AND state = 'pending'
                """,
            arguments: [babyID, nowMilliseconds, request.commandID]
        )
        guard database.changesCount == 1 else {
            throw OnboardingError.inconsistentState
        }

        return OnboardingSnapshot(
            localVaultID: vaultID,
            localActorID: actorID,
            baby: BabyProfileSnapshot(
                id: babyID,
                nickname: request.nickname,
                birthLocalDate: request.birthLocalDate,
                growthReferenceGroup: request.growthReferenceGroup,
                homeTimeZone: request.homeTimeZone
            ),
            lactatingProfileID: lactatingProfileID,
            enabledModules: request.enabledModules,
            homeModules: request.homeModules
        )
    }

    private static func loadCompleteSnapshot(
        _ database: Database,
        security: OnboardingSecurityMaterial
    ) throws -> OnboardingSnapshot {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT
                    v.id AS vault_id,
                    v.state AS vault_state,
                    a.id AS actor_id,
                    a.trust_model AS trust_model,
                    a.guardian_declared AS guardian_declared,
                    d.id AS installation_id,
                    d.restore_sentinel_hash AS sentinel_hash,
                    d.backup_policy_generation AS backup_generation,
                    d.schema_version AS installation_schema_version,
                    d.media_layout_version AS installation_media_version,
                    d.schema_fingerprint AS installation_fingerprint,
                    b.id AS baby_id,
                    b.nickname AS nickname,
                    b.birth_local_date AS birth_local_date,
                    b.growth_group AS growth_group,
                    b.home_time_zone AS home_time_zone,
                    b.created_at_ms AS baby_created_at_ms,
                    c.policy_version AS child_policy_version,
                    c.scope_json AS child_scope_json,
                    c.notice_sha256 AS child_notice_sha256
                FROM local_vault v
                JOIN local_actor a ON a.local_vault_id = v.id
                JOIN device_installation d
                  ON d.local_vault_id = v.id AND d.state = 'active'
                JOIN baby_profile b
                  ON b.local_vault_id = v.id AND b.deleted_at_ms IS NULL
                JOIN consent_record c
                  ON c.id = b.current_consent_id
                 AND c.local_vault_id = v.id
                 AND c.subject_type = 'child'
                 AND c.baby_id = b.id
                 AND c.guardian_actor_id = a.id
                 AND c.withdrawn_at_ms IS NULL
                WHERE v.singleton_slot = 1
                """
        )
        guard rows.count == 1 else {
            throw OnboardingError.inconsistentState
        }
        let row = rows[0]
        let vaultID: String = row["vault_id"]
        let actorID: String = row["actor_id"]
        let babyID: String = row["baby_id"]
        let nickname: String = row["nickname"]
        let birthLocalDate: String = row["birth_local_date"]
        let growthGroupRaw: String = row["growth_group"]
        let homeTimeZone: String = row["home_time_zone"]
        let installationID: String = row["installation_id"]
        let sentinelHash: String = row["sentinel_hash"]

        guard (row["vault_state"] as String) == "active",
              (row["trust_model"] as String) == "single_trusted_adult",
              (row["guardian_declared"] as Int) == 1,
              isCanonicalUUID(vaultID),
              isCanonicalUUID(actorID),
              isCanonicalUUID(babyID),
              isCanonicalUUID(installationID),
              isLowercaseSHA256(sentinelHash),
              installationID == security.deviceInstallationID,
              sentinelHash == security.restoreSentinelHash,
              (row["backup_generation"] as Int) == 1,
              (row["installation_schema_version"] as Int) == SchemaContract.currentVersion,
              (row["installation_media_version"] as Int) == SchemaContract.mediaLayoutVersion,
              (row["installation_fingerprint"] as String) == SchemaContract.expectedFingerprint,
              let growthGroup = GrowthReferenceGroup(rawValue: growthGroupRaw) else {
            throw OnboardingError.inconsistentState
        }
        try validateStoredBaby(
            nickname: nickname,
            birthLocalDate: birthLocalDate,
            homeTimeZone: homeTimeZone,
            createdAtMilliseconds: row["baby_created_at_ms"]
        )
        try validateStoredConsent(
            policyVersion: row["child_policy_version"],
            scopeJSON: row["child_scope_json"],
            noticeSHA256: row["child_notice_sha256"],
            expected: OnboardingConsentPolicy.child
        )

        let moduleRows = try Row.fetchAll(
            database,
            sql: """
                SELECT module_type, is_enabled, home_position
                FROM module_preference
                WHERE local_vault_id = ?
                """,
            arguments: [vaultID]
        )
        guard moduleRows.count == HomeModule.allCases.count else {
            throw OnboardingError.inconsistentState
        }
        var enabledModules: [HomeModule] = []
        var positionedModules: [(position: Int, module: HomeModule)] = []
        var seenModules = Set<HomeModule>()
        for moduleRow in moduleRows {
            let raw: String = moduleRow["module_type"]
            let isEnabled: Int = moduleRow["is_enabled"]
            guard let module = HomeModule(rawValue: raw),
                  seenModules.insert(module).inserted,
                  isEnabled == 0 || isEnabled == 1 else {
                throw OnboardingError.inconsistentState
            }
            if isEnabled == 1 { enabledModules.append(module) }
            if let position: Int = moduleRow["home_position"] {
                guard isEnabled == 1, (1...4).contains(position) else {
                    throw OnboardingError.inconsistentState
                }
                positionedModules.append((position, module))
            }
        }
        enabledModules = HomeModule.allCases.filter(Set(enabledModules).contains)
        positionedModules.sort { $0.position < $1.position }
        guard positionedModules.map(\.position) == Array(1...positionedModules.count) else {
            throw OnboardingError.inconsistentState
        }
        let homeModules = positionedModules.map(\.module)

        let needsAdult = enabledModules.contains(.nursing) || enabledModules.contains(.pumping)
        let adultRows = try Row.fetchAll(
            database,
            sql: """
                SELECT
                    p.id AS profile_id,
                    p.home_time_zone AS home_time_zone,
                    c.policy_version AS policy_version,
                    c.scope_json AS scope_json,
                    c.notice_sha256 AS notice_sha256
                FROM lactating_profile p
                JOIN consent_record c
                  ON c.id = p.current_consent_id
                 AND c.local_vault_id = p.local_vault_id
                 AND c.subject_type = 'adult'
                 AND c.lactating_profile_id = p.id
                 AND c.adult_actor_id = p.owner_actor_id
                 AND c.withdrawn_at_ms IS NULL
                WHERE p.local_vault_id = ?
                  AND p.owner_actor_id = ?
                  AND p.deleted_at_ms IS NULL
                """,
            arguments: [vaultID, actorID]
        )
        let lactatingProfileID: String?
        if needsAdult {
            guard adultRows.count == 1 else {
                throw OnboardingError.inconsistentState
            }
            let adultRow = adultRows[0]
            guard (adultRow["home_time_zone"] as String) == homeTimeZone else {
                throw OnboardingError.inconsistentState
            }
            try validateStoredConsent(
                policyVersion: adultRow["policy_version"],
                scopeJSON: adultRow["scope_json"],
                noticeSHA256: adultRow["notice_sha256"],
                expected: OnboardingConsentPolicy.adultLactation
            )
            let profileID: String = adultRow["profile_id"]
            guard isCanonicalUUID(profileID) else {
                throw OnboardingError.inconsistentState
            }
            lactatingProfileID = profileID
        } else {
            guard adultRows.isEmpty,
                  try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM lactating_profile WHERE deleted_at_ms IS NULL"
                  ) == 0 else {
                throw OnboardingError.inconsistentState
            }
            lactatingProfileID = nil
        }

        let ledgerRows = try Row.fetchAll(
            database,
            sql: """
                SELECT command_id, input_sha256
                FROM operation_ledger
                WHERE local_vault_id = ?
                  AND operation_type = ?
                  AND state = 'succeeded'
                  AND result_type = 'baby_profile'
                  AND result_id = ?
                  AND result_revision = 1
            """,
            arguments: [vaultID, operationType, babyID]
        )
        guard ledgerRows.count == 1 else {
            throw OnboardingError.inconsistentState
        }
        let ledgerCommandID: String = ledgerRows[0]["command_id"]
        let ledgerInputSHA256: String = ledgerRows[0]["input_sha256"]
        guard isCanonicalUUID(ledgerCommandID),
              isLowercaseSHA256(ledgerInputSHA256) else {
            throw OnboardingError.inconsistentState
        }

        return OnboardingSnapshot(
            localVaultID: vaultID,
            localActorID: actorID,
            baby: BabyProfileSnapshot(
                id: babyID,
                nickname: nickname,
                birthLocalDate: birthLocalDate,
                growthReferenceGroup: growthGroup,
                homeTimeZone: homeTimeZone
            ),
            lactatingProfileID: lactatingProfileID,
            enabledModules: enabledModules,
            homeModules: homeModules
        )
    }

    private static func insertChildConsent(
        _ evidence: ValidatedConsentEvidence,
        id: String,
        vaultID: String,
        babyID: String,
        actorID: String,
        grantedAtMilliseconds: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO consent_record (
                    id, local_vault_id, subject_type, baby_id,
                    guardian_actor_id, policy_version, scope_json,
                    notice_sha256, granted_at_ms
                ) VALUES (?, ?, 'child', ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                vaultID,
                babyID,
                actorID,
                evidence.policyVersion,
                evidence.scopeJSON,
                evidence.noticeSHA256,
                grantedAtMilliseconds,
            ]
        )
    }

    private static func insertAdultConsent(
        _ evidence: ValidatedConsentEvidence,
        id: String,
        vaultID: String,
        profileID: String,
        actorID: String,
        grantedAtMilliseconds: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO consent_record (
                    id, local_vault_id, subject_type, lactating_profile_id,
                    adult_actor_id, policy_version, scope_json,
                    notice_sha256, granted_at_ms
                ) VALUES (?, ?, 'adult', ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                vaultID,
                profileID,
                actorID,
                evidence.policyVersion,
                evidence.scopeJSON,
                evidence.noticeSHA256,
                grantedAtMilliseconds,
            ]
        )
    }

    private static func existingCommand(
        _ commandID: String,
        database: Database
    ) throws -> ExistingCommand? {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT operation_type, input_sha256, state,
                       result_type, result_id, result_revision
                FROM operation_ledger
                WHERE command_id = ?
                """,
            arguments: [commandID]
        ) else {
            return nil
        }
        return ExistingCommand(
            operationType: row["operation_type"],
            inputSHA256: row["input_sha256"],
            state: row["state"],
            resultType: row["result_type"],
            resultID: row["result_id"],
            resultRevision: row["result_revision"]
        )
    }

    private static func makeUniqueID(
        uuid: any UUIDGenerating,
        used: inout Set<String>
    ) throws -> String {
        for _ in 0..<16 {
            let value = uuid.makeUUID().uuidString.lowercased()
            if used.insert(value).inserted { return value }
        }
        throw OnboardingError.inconsistentState
    }

    private static func snapshotMatchesValidatedInput(
        _ snapshot: OnboardingSnapshot,
        request: ValidatedOnboardingRequest
    ) -> Bool {
        snapshot.baby.nickname == request.nickname &&
            snapshot.baby.birthLocalDate == request.birthLocalDate &&
            snapshot.baby.growthReferenceGroup == request.growthReferenceGroup &&
            snapshot.baby.homeTimeZone == request.homeTimeZone &&
            snapshot.enabledModules == request.enabledModules &&
            snapshot.homeModules == request.homeModules &&
            (snapshot.lactatingProfileID != nil) ==
                (request.adultLactationConsent != nil)
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func validateStoredBaby(
        nickname: String,
        birthLocalDate: String,
        homeTimeZone: String,
        createdAtMilliseconds: Int64
    ) throws {
        do {
            try OnboardingRequestValidator.validateStoredBaby(
                nickname: nickname,
                birthLocalDate: birthLocalDate,
                homeTimeZone: homeTimeZone,
                createdAtMilliseconds: createdAtMilliseconds
            )
        } catch {
            throw OnboardingError.inconsistentState
        }
    }

    private static func validateStoredConsent(
        policyVersion: String,
        scopeJSON: String,
        noticeSHA256: String,
        expected: OnboardingConsentPolicy.Contract
    ) throws {
        guard policyVersion == expected.policyVersion,
              scopeJSON == expected.scopeJSON,
              noticeSHA256 == expected.noticeSHA256 else {
            throw OnboardingError.inconsistentState
        }
    }
}

private struct ExistingCommand: Sendable {
    let operationType: String
    let inputSHA256: String
    let state: String
    let resultType: String?
    let resultID: String?
    let resultRevision: Int?
}
