PRAGMA application_id = 1296187993; -- 0x4D424259, "MBBY"
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
PRAGMA secure_delete = ON;
PRAGMA temp_store = MEMORY;

CREATE TABLE schema_metadata (
    singleton_slot INTEGER PRIMARY KEY CHECK (singleton_slot = 1),
    application_id INTEGER NOT NULL CHECK (application_id = 1296187993),
    schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
    media_layout_version INTEGER NOT NULL CHECK (media_layout_version >= 1),
    schema_fingerprint TEXT NOT NULL CHECK (length(schema_fingerprint) = 64),
    installed_at_ms INTEGER NOT NULL CHECK (installed_at_ms > 0)
) STRICT;

CREATE TABLE local_vault (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    singleton_slot INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK (singleton_slot = 1),
    state TEXT NOT NULL CHECK (state IN ('active','protection_blocked','deleting','recovery_required')),
    data_revision INTEGER NOT NULL DEFAULT 0 CHECK (data_revision >= 0),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
) STRICT;

CREATE TABLE local_actor (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL UNIQUE
        REFERENCES local_vault(id) ON DELETE CASCADE,
    trust_model TEXT NOT NULL DEFAULT 'single_trusted_adult'
        CHECK (trust_model = 'single_trusted_adult'),
    guardian_declared INTEGER NOT NULL CHECK (guardian_declared IN (0,1)),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
) STRICT;

CREATE TABLE device_installation (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK (state IN ('active','replaced','restored','revoked')),
    schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
    media_layout_version INTEGER NOT NULL CHECK (media_layout_version >= 1),
    schema_fingerprint TEXT NOT NULL CHECK (length(schema_fingerprint) = 64),
    restore_sentinel_hash TEXT NOT NULL CHECK (length(restore_sentinel_hash) = 64),
    backup_policy_generation INTEGER NOT NULL CHECK (backup_policy_generation >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    replaced_at_ms INTEGER NULL CHECK (replaced_at_ms IS NULL OR replaced_at_ms >= created_at_ms)
) STRICT;

CREATE UNIQUE INDEX one_active_installation_per_vault
ON device_installation(local_vault_id) WHERE state = 'active';

CREATE TABLE app_setting (
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    setting_key TEXT NOT NULL,
    value_json TEXT NOT NULL CHECK (json_valid(value_json)),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms > 0),
    PRIMARY KEY (local_vault_id, setting_key)
) STRICT, WITHOUT ROWID;

CREATE TABLE module_preference (
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    module_type TEXT NOT NULL CHECK (module_type IN ('nursing','pumping','bottle','diaper','sleep','growth','moments','supplies')),
    is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0,1)),
    home_position INTEGER NULL CHECK (home_position BETWEEN 1 AND 4),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms > 0),
    PRIMARY KEY (local_vault_id, module_type)
) STRICT, WITHOUT ROWID;

CREATE UNIQUE INDEX unique_home_module_position
ON module_preference(local_vault_id, home_position)
WHERE home_position IS NOT NULL;

CREATE TABLE growth_standard_version (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    standard_code TEXT NOT NULL,
    version TEXT NOT NULL,
    source_url TEXT NOT NULL,
    resource_sha256 TEXT NOT NULL CHECK (length(resource_sha256) = 64),
    is_active INTEGER NOT NULL CHECK (is_active IN (0,1)),
    installed_at_ms INTEGER NOT NULL CHECK (installed_at_ms > 0),
    UNIQUE (standard_code, version)
) STRICT;

CREATE UNIQUE INDEX one_active_growth_standard
ON growth_standard_version(standard_code) WHERE is_active = 1;

-- References to baby_profile/lactating_profile are deferred because onboarding
-- creates consent first, then the subject, in one transaction.
CREATE TABLE consent_record (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    subject_type TEXT NOT NULL CHECK (subject_type IN ('child','adult')),
    baby_id TEXT NULL REFERENCES baby_profile(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    lactating_profile_id TEXT NULL REFERENCES lactating_profile(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    guardian_actor_id TEXT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    adult_actor_id TEXT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    policy_version TEXT NOT NULL,
    scope_json TEXT NOT NULL CHECK (json_valid(scope_json)),
    notice_sha256 TEXT NOT NULL CHECK (length(notice_sha256) = 64),
    granted_at_ms INTEGER NOT NULL CHECK (granted_at_ms > 0),
    withdrawn_at_ms INTEGER NULL CHECK (withdrawn_at_ms IS NULL OR withdrawn_at_ms >= granted_at_ms),
    CHECK (
      (subject_type = 'child' AND baby_id IS NOT NULL AND lactating_profile_id IS NULL
       AND guardian_actor_id IS NOT NULL AND adult_actor_id IS NULL)
      OR
      (subject_type = 'adult' AND baby_id IS NULL AND lactating_profile_id IS NOT NULL
       AND guardian_actor_id IS NULL AND adult_actor_id IS NOT NULL)
    )
) STRICT;

CREATE INDEX consent_by_subject
ON consent_record(subject_type, baby_id, lactating_profile_id, granted_at_ms DESC);

CREATE TABLE baby_profile (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    nickname TEXT NOT NULL CHECK (length(CAST(nickname AS BLOB)) BETWEEN 1 AND 512),
    birth_local_date TEXT NOT NULL CHECK (
        length(birth_local_date) = 10
        AND birth_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(birth_local_date, '+0 days') IS NOT NULL
        AND date(birth_local_date, '+0 days') = birth_local_date),
    growth_group TEXT NOT NULL CHECK (growth_group IN ('male','female','unspecified')),
    home_time_zone TEXT NOT NULL CHECK (length(home_time_zone) BETWEEN 1 AND 64),
    grouping_generation INTEGER NOT NULL DEFAULT 1 CHECK (grouping_generation >= 1),
    avatar_asset_id TEXT NULL REFERENCES media_asset(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    current_consent_id TEXT NOT NULL
        REFERENCES consent_record(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE UNIQUE INDEX one_active_baby_per_vault
ON baby_profile(local_vault_id) WHERE deleted_at_ms IS NULL;

CREATE TABLE lactating_profile (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    owner_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    home_time_zone TEXT NOT NULL CHECK (length(home_time_zone) BETWEEN 1 AND 64),
    grouping_generation INTEGER NOT NULL DEFAULT 1 CHECK (grouping_generation >= 1),
    current_consent_id TEXT NOT NULL
        REFERENCES consent_record(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE UNIQUE INDEX one_active_lactating_profile_per_actor
ON lactating_profile(owner_actor_id) WHERE deleted_at_ms IS NULL;

CREATE TABLE operation_ledger (
    command_id TEXT PRIMARY KEY CHECK (length(command_id) = 36 AND command_id = lower(command_id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    operation_type TEXT NOT NULL,
    target_type TEXT NULL,
    target_id TEXT NULL,
    expected_revision INTEGER NULL CHECK (expected_revision IS NULL OR expected_revision >= 1),
    input_sha256 TEXT NOT NULL CHECK (length(input_sha256) = 64),
    state TEXT NOT NULL CHECK (state IN ('pending','succeeded','failed')),
    result_type TEXT NULL,
    result_id TEXT NULL,
    result_revision INTEGER NULL CHECK (result_revision IS NULL OR result_revision >= 1),
    error_group TEXT NULL,
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    completed_at_ms INTEGER NULL CHECK (completed_at_ms IS NULL OR completed_at_ms >= created_at_ms),
    CHECK ((state = 'pending' AND completed_at_ms IS NULL)
        OR (state IN ('succeeded','failed') AND completed_at_ms IS NOT NULL))
) STRICT;

CREATE INDEX operation_ledger_cleanup
ON operation_ledger(state, completed_at_ms);

CREATE TABLE care_event (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('nursing','bottle','diaper','sleep')),
    occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms > 0),
    ended_at_ms INTEGER NULL CHECK (ended_at_ms IS NULL OR ended_at_ms >= occurred_at_ms),
    event_time_zone TEXT NOT NULL CHECK (length(event_time_zone) BETWEEN 1 AND 64),
    event_utc_offset_seconds INTEGER NOT NULL CHECK (event_utc_offset_seconds BETWEEN -64800 AND 64800),
    ended_utc_offset_seconds INTEGER NULL CHECK (ended_utc_offset_seconds BETWEEN -64800 AND 64800),
    group_local_date TEXT NOT NULL CHECK (
        length(group_local_date) = 10
        AND group_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(group_local_date, '+0 days') IS NOT NULL
        AND date(group_local_date, '+0 days') = group_local_date),
    note TEXT NULL CHECK (note IS NULL OR length(CAST(note AS BLOB)) <= 8192),
    source_timer_session_id TEXT NULL UNIQUE
        REFERENCES timer_session(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms),
    CHECK ((ended_at_ms IS NULL AND ended_utc_offset_seconds IS NULL)
        OR (ended_at_ms IS NOT NULL AND ended_utc_offset_seconds IS NOT NULL)),
    CHECK ((type IN ('nursing','sleep') AND ended_at_ms IS NOT NULL) OR type IN ('bottle','diaper')),
    CHECK (type <> 'sleep' OR ended_at_ms - occurred_at_ms <= 172800000),
    CHECK (type <> 'nursing' OR ended_at_ms - occurred_at_ms <= 43200000),
    CHECK (type <> 'diaper' OR ended_at_ms IS NULL)
) STRICT;

CREATE INDEX care_event_timeline
ON care_event(baby_id, deleted_at_ms, occurred_at_ms DESC, created_at_ms DESC, id DESC);
CREATE INDEX care_event_by_type
ON care_event(baby_id, type, deleted_at_ms, occurred_at_ms DESC);
CREATE INDEX care_event_by_day
ON care_event(baby_id, group_local_date DESC, deleted_at_ms, occurred_at_ms DESC);

CREATE TABLE feeding_detail (
    event_id TEXT PRIMARY KEY REFERENCES care_event(id) ON DELETE CASCADE,
    mode TEXT NOT NULL CHECK (mode IN ('nursing','bottle')),
    milk_type TEXT NULL CHECK (milk_type IN ('breast_milk','formula')),
    nursing_total_seconds INTEGER NULL CHECK (nursing_total_seconds BETWEEN 0 AND 43200),
    amount_ml INTEGER NULL CHECK (amount_ml BETWEEN 1 AND 2000),
    CHECK (
      (mode = 'nursing' AND milk_type = 'breast_milk'
       AND nursing_total_seconds IS NOT NULL AND amount_ml IS NULL)
      OR
      (mode = 'bottle' AND milk_type IS NOT NULL
       AND nursing_total_seconds IS NULL AND amount_ml IS NOT NULL)
    )
) STRICT;

CREATE TABLE diaper_detail (
    event_id TEXT PRIMARY KEY REFERENCES care_event(id) ON DELETE CASCADE,
    diaper_type TEXT NOT NULL CHECK (diaper_type IN ('wet','dirty','both'))
) STRICT;

CREATE TABLE timer_session (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    type TEXT NOT NULL CHECK (type IN ('nursing','pumping','sleep')),
    baby_id TEXT NULL REFERENCES baby_profile(id) ON DELETE RESTRICT,
    baby_context_detached_at_ms INTEGER NULL
        CHECK (baby_context_detached_at_ms IS NULL OR baby_context_detached_at_ms > 0),
    lactating_profile_id TEXT NULL REFERENCES lactating_profile(id) ON DELETE CASCADE,
    selected_mode TEXT NOT NULL CHECK (selected_mode IN ('left','right','bilateral','generic')),
    state TEXT NOT NULL CHECK (state IN ('ready','running','paused','waiting_for_side','finalizing','finished','abandoned')),
    clock_verification_state TEXT NOT NULL CHECK (clock_verification_state IN ('verified_current_process','wall_only_after_process_loss','user_confirmed','not_applicable')),
    started_at_ms INTEGER NOT NULL CHECK (started_at_ms > 0),
    last_activity_at_ms INTEGER NOT NULL CHECK (last_activity_at_ms >= started_at_ms),
    ended_at_ms INTEGER NULL CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
    origin_device_installation_id TEXT NOT NULL REFERENCES device_installation(id) ON DELETE RESTRICT,
    start_command_id TEXT NOT NULL UNIQUE,
    finish_command_id TEXT NULL UNIQUE,
    final_care_event_id TEXT NULL UNIQUE REFERENCES care_event(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    final_pumping_record_id TEXT NULL UNIQUE REFERENCES pumping_record(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms),
    CHECK (
      (type = 'nursing' AND lactating_profile_id IS NOT NULL AND selected_mode IN ('left','right')
       AND (baby_id IS NOT NULL OR baby_context_detached_at_ms IS NOT NULL))
      OR (type = 'pumping' AND lactating_profile_id IS NOT NULL AND selected_mode IN ('left','right','bilateral'))
      OR (type = 'sleep' AND baby_id IS NOT NULL AND lactating_profile_id IS NULL
       AND selected_mode = 'generic' AND baby_context_detached_at_ms IS NULL)
    ),
    CHECK (
      baby_context_detached_at_ms IS NULL
      OR (baby_id IS NULL AND type IN ('nursing','pumping')
       AND baby_context_detached_at_ms >= started_at_ms)
    ),
    CHECK (type <> 'nursing' OR baby_id IS NOT NULL OR state IN ('finalizing','finished','abandoned')),
    CHECK (type <> 'pumping' OR baby_id IS NOT NULL OR baby_context_detached_at_ms IS NULL
      OR baby_context_detached_at_ms >= started_at_ms),
    CHECK (type <> 'sleep' OR baby_context_detached_at_ms IS NULL),
    CHECK (
      (baby_id IS NOT NULL AND baby_context_detached_at_ms IS NULL)
      OR baby_id IS NULL
    ),
    CHECK (
      (state = 'finished' AND ended_at_ms IS NOT NULL AND finish_command_id IS NOT NULL
       AND (
         (type = 'pumping' AND final_pumping_record_id IS NOT NULL AND final_care_event_id IS NULL)
         OR (type = 'sleep' AND final_care_event_id IS NOT NULL AND final_pumping_record_id IS NULL)
         OR (type = 'nursing' AND final_pumping_record_id IS NULL AND (
           (baby_id IS NOT NULL AND baby_context_detached_at_ms IS NULL AND final_care_event_id IS NOT NULL)
           OR (baby_id IS NULL AND baby_context_detached_at_ms IS NOT NULL AND final_care_event_id IS NULL)
         ))
       ))
      OR
      (state <> 'finished' AND final_care_event_id IS NULL AND final_pumping_record_id IS NULL)
    ),
    CHECK (state NOT IN ('finished','abandoned') OR ended_at_ms IS NOT NULL)
) STRICT;

CREATE UNIQUE INDEX one_active_nursing_per_baby
ON timer_session(baby_id)
WHERE type = 'nursing' AND deleted_at_ms IS NULL
  AND state IN ('ready','running','paused','waiting_for_side','finalizing');

CREATE UNIQUE INDEX one_active_sleep_per_baby
ON timer_session(baby_id)
WHERE type = 'sleep' AND deleted_at_ms IS NULL
  AND state IN ('ready','running','paused','finalizing');

CREATE UNIQUE INDEX one_active_pumping_per_profile
ON timer_session(lactating_profile_id)
WHERE type = 'pumping' AND deleted_at_ms IS NULL
  AND state IN ('ready','running','paused','waiting_for_side','finalizing');

CREATE INDEX timer_session_recovery
ON timer_session(state, last_activity_at_ms) WHERE deleted_at_ms IS NULL;

CREATE TABLE timer_channel (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    session_id TEXT NOT NULL REFERENCES timer_session(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel IN ('left','right','generic')),
    is_selected INTEGER NOT NULL CHECK (is_selected IN (0,1)),
    state TEXT NOT NULL CHECK (state IN ('not_started','running','paused','ended','abandoned')),
    total_seconds_cache INTEGER NOT NULL DEFAULT 0 CHECK (total_seconds_cache BETWEEN 0 AND 43200),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    UNIQUE (session_id, channel),
    CHECK ((is_selected = 0 AND state = 'abandoned') OR is_selected = 1)
) STRICT;

CREATE TABLE timer_segment (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    channel_id TEXT NOT NULL REFERENCES timer_channel(id) ON DELETE CASCADE,
    started_at_ms INTEGER NOT NULL CHECK (started_at_ms > 0),
    ended_at_ms INTEGER NULL CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
    start_command_id TEXT NOT NULL,
    end_command_id TEXT NULL,
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    CHECK ((ended_at_ms IS NULL AND end_command_id IS NULL)
        OR (ended_at_ms IS NOT NULL AND end_command_id IS NOT NULL)),
    UNIQUE (start_command_id, channel_id),
    UNIQUE (end_command_id, channel_id)
) STRICT;

CREATE UNIQUE INDEX one_open_segment_per_channel
ON timer_segment(channel_id) WHERE ended_at_ms IS NULL;
CREATE INDEX timer_segment_timeline
ON timer_segment(channel_id, started_at_ms, ended_at_ms);

CREATE TABLE active_resource_lock (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    lock_kind TEXT NOT NULL CHECK (lock_kind IN ('baby_nursing','baby_sleep','adult_pumping','adult_side')),
    baby_id TEXT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    lactating_profile_id TEXT NULL REFERENCES lactating_profile(id) ON DELETE CASCADE,
    side TEXT NULL CHECK (side IN ('left','right')),
    session_id TEXT NOT NULL REFERENCES timer_session(id) ON DELETE CASCADE,
    channel_id TEXT NULL REFERENCES timer_channel(id) ON DELETE CASCADE,
    acquired_at_ms INTEGER NOT NULL CHECK (acquired_at_ms > 0),
    CHECK (
      (lock_kind IN ('baby_nursing','baby_sleep') AND baby_id IS NOT NULL
       AND lactating_profile_id IS NULL AND side IS NULL AND channel_id IS NULL)
      OR (lock_kind = 'adult_pumping' AND baby_id IS NULL
       AND lactating_profile_id IS NOT NULL AND side IS NULL AND channel_id IS NULL)
      OR (lock_kind = 'adult_side' AND baby_id IS NULL
       AND lactating_profile_id IS NOT NULL AND side IS NOT NULL AND channel_id IS NOT NULL)
    )
) STRICT;

CREATE UNIQUE INDEX unique_baby_nursing_lock
ON active_resource_lock(baby_id) WHERE lock_kind = 'baby_nursing';
CREATE UNIQUE INDEX unique_baby_sleep_lock
ON active_resource_lock(baby_id) WHERE lock_kind = 'baby_sleep';
CREATE UNIQUE INDEX unique_adult_pumping_lock
ON active_resource_lock(lactating_profile_id) WHERE lock_kind = 'adult_pumping';
CREATE UNIQUE INDEX unique_adult_side_lock
ON active_resource_lock(lactating_profile_id, side) WHERE lock_kind = 'adult_side';
CREATE UNIQUE INDEX unique_lock_shape_per_session
ON active_resource_lock(session_id, lock_kind, ifnull(side, 'none'));

CREATE TABLE nursing_side_detail (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    related_event_id TEXT NULL REFERENCES care_event(id) ON DELETE RESTRICT,
    lactating_profile_id TEXT NOT NULL REFERENCES lactating_profile(id) ON DELETE CASCADE,
    timer_session_id TEXT NOT NULL UNIQUE
        REFERENCES timer_session(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    left_seconds_cache INTEGER NOT NULL DEFAULT 0 CHECK (left_seconds_cache BETWEEN 0 AND 43200),
    right_seconds_cache INTEGER NOT NULL DEFAULT 0 CHECK (right_seconds_cache BETWEEN 0 AND 43200),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE UNIQUE INDEX one_active_nursing_detail_per_event
ON nursing_side_detail(related_event_id)
WHERE related_event_id IS NOT NULL AND deleted_at_ms IS NULL;

CREATE TABLE pumping_record (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    lactating_profile_id TEXT NOT NULL REFERENCES lactating_profile(id) ON DELETE CASCADE,
    related_baby_id TEXT NULL REFERENCES baby_profile(id) ON DELETE RESTRICT,
    related_baby_local_date TEXT NULL CHECK (
        related_baby_local_date IS NULL OR (
          length(related_baby_local_date) = 10
          AND related_baby_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
          AND date(related_baby_local_date, '+0 days') IS NOT NULL
          AND date(related_baby_local_date, '+0 days') = related_baby_local_date)),
    occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms > 0),
    ended_at_ms INTEGER NOT NULL CHECK (ended_at_ms >= occurred_at_ms),
    event_time_zone TEXT NOT NULL CHECK (length(event_time_zone) BETWEEN 1 AND 64),
    event_utc_offset_seconds INTEGER NOT NULL CHECK (event_utc_offset_seconds BETWEEN -64800 AND 64800),
    ended_utc_offset_seconds INTEGER NOT NULL CHECK (ended_utc_offset_seconds BETWEEN -64800 AND 64800),
    pattern TEXT NOT NULL CHECK (pattern IN ('single_left','single_right','bilateral_simultaneous','bilateral_sequential')),
    left_ml INTEGER NULL CHECK (left_ml BETWEEN 0 AND 2000),
    right_ml INTEGER NULL CHECK (right_ml BETWEEN 0 AND 2000),
    total_ml INTEGER NULL CHECK (total_ml BETWEEN 0 AND 2000),
    effective_seconds_cache INTEGER NOT NULL CHECK (effective_seconds_cache BETWEEN 0 AND 43200),
    timer_session_id TEXT NOT NULL UNIQUE
        REFERENCES timer_session(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    note TEXT NULL CHECK (note IS NULL OR length(CAST(note AS BLOB)) <= 8192),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms),
    CHECK ((related_baby_id IS NULL AND related_baby_local_date IS NULL)
        OR (related_baby_id IS NOT NULL AND related_baby_local_date IS NOT NULL)),
    CHECK (
      (left_ml IS NULL AND right_ml IS NULL)
      OR (total_ml IS NOT NULL AND total_ml = ifnull(left_ml,0) + ifnull(right_ml,0))
    )
) STRICT;

CREATE INDEX pumping_timeline
ON pumping_record(lactating_profile_id, deleted_at_ms, occurred_at_ms DESC, created_at_ms DESC, id DESC);
CREATE INDEX pumping_related_baby
ON pumping_record(related_baby_id, related_baby_local_date) WHERE related_baby_id IS NOT NULL;

CREATE TABLE growth_record (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    measured_local_date TEXT NOT NULL CHECK (
        length(measured_local_date) = 10
        AND measured_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(measured_local_date, '+0 days') IS NOT NULL
        AND date(measured_local_date, '+0 days') = measured_local_date),
    measurement_type TEXT NULL CHECK (measurement_type IN ('recumbent_length','standing_height')),
    weight_grams INTEGER NULL CHECK (weight_grams BETWEEN 100 AND 50000),
    length_mm INTEGER NULL CHECK (length_mm BETWEEN 200 AND 1500),
    note TEXT NULL CHECK (note IS NULL OR length(CAST(note AS BLOB)) <= 8192),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms),
    CHECK (weight_grams IS NOT NULL OR length_mm IS NOT NULL),
    CHECK ((length_mm IS NULL AND measurement_type IS NULL)
        OR (length_mm IS NOT NULL AND measurement_type IS NOT NULL))
) STRICT;

CREATE INDEX growth_timeline
ON growth_record(baby_id, measured_local_date DESC, deleted_at_ms, created_at_ms DESC, id DESC);

-- Immutable supply identity. Repository pre-generates both IDs, inserts the
-- deferred version row first, then its subject/current pointer in one transaction.
CREATE TABLE formula_product (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    current_version_id TEXT NOT NULL
        REFERENCES formula_product_version(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    status TEXT NOT NULL CHECK (status IN ('active','inactive')),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE TABLE formula_product_version (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    product_id TEXT NOT NULL REFERENCES formula_product(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    version INTEGER NOT NULL CHECK (version >= 1),
    brand TEXT NOT NULL CHECK (length(CAST(brand AS BLOB)) BETWEEN 1 AND 1024),
    product_name TEXT NOT NULL CHECK (length(CAST(product_name AS BLOB)) BETWEEN 1 AND 1024),
    stage_or_age TEXT NOT NULL CHECK (length(CAST(stage_or_age AS BLOB)) BETWEEN 1 AND 1024),
    specification TEXT NOT NULL CHECK (length(CAST(specification AS BLOB)) BETWEEN 1 AND 1024),
    manufacturer TEXT NOT NULL CHECK (length(CAST(manufacturer AS BLOB)) BETWEEN 1 AND 1024),
    origin_country TEXT NULL,
    importer TEXT NULL,
    formula_registration_no TEXT NULL,
    gtin TEXT NULL,
    content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    UNIQUE (product_id, version)
) STRICT;

CREATE TABLE formula_container (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    product_id TEXT NOT NULL REFERENCES formula_product(id) ON DELETE CASCADE,
    current_version_id TEXT NOT NULL
        REFERENCES formula_container_version(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    opened_at_ms INTEGER NULL CHECK (opened_at_ms > 0),
    status TEXT NOT NULL CHECK (status IN ('active','finished','discarded','inactive')),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE TABLE formula_container_version (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    container_id TEXT NOT NULL REFERENCES formula_container(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    version INTEGER NOT NULL CHECK (version >= 1),
    product_version_id TEXT NOT NULL REFERENCES formula_product_version(id) ON DELETE RESTRICT,
    lot_number_raw TEXT NULL CHECK (lot_number_raw IS NULL OR length(CAST(lot_number_raw AS BLOB)) <= 1024),
    produced_local_date TEXT NULL CHECK (produced_local_date IS NULL OR (
        length(produced_local_date) = 10
        AND produced_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(produced_local_date, '+0 days') IS NOT NULL AND date(produced_local_date, '+0 days') = produced_local_date)),
    expires_local_date TEXT NULL CHECK (expires_local_date IS NULL OR (
        length(expires_local_date) = 10
        AND expires_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(expires_local_date, '+0 days') IS NOT NULL AND date(expires_local_date, '+0 days') = expires_local_date)),
    printed_date_raw TEXT NULL CHECK (printed_date_raw IS NULL OR length(CAST(printed_date_raw AS BLOB)) <= 1024),
    purchased_local_date TEXT NULL CHECK (purchased_local_date IS NULL OR (
        length(purchased_local_date) = 10
        AND purchased_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(purchased_local_date, '+0 days') IS NOT NULL AND date(purchased_local_date, '+0 days') = purchased_local_date)),
    seller_or_channel TEXT NULL CHECK (seller_or_channel IS NULL OR length(CAST(seller_or_channel AS BLOB)) <= 2048),
    trace_provider TEXT NULL,
    enterprise_code TEXT NULL,
    code_symbology TEXT NULL,
    trace_code_raw TEXT NULL CHECK (trace_code_raw IS NULL OR length(CAST(trace_code_raw AS BLOB)) <= 8192),
    trace_code_normalized TEXT NULL CHECK (trace_code_normalized IS NULL OR length(CAST(trace_code_normalized AS BLOB)) <= 8192),
    verification_status TEXT NOT NULL CHECK (verification_status IN ('draft','user_confirmed','recall_ready')),
    content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    UNIQUE (container_id, version),
    CHECK (produced_local_date IS NULL OR expires_local_date IS NULL OR produced_local_date <= expires_local_date)
) STRICT;

CREATE INDEX formula_container_active
ON formula_container(product_id, status, opened_at_ms DESC) WHERE deleted_at_ms IS NULL;
CREATE INDEX formula_trace_search
ON formula_container_version(trace_provider, trace_code_normalized);

CREATE TABLE bottle_item (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    current_version_id TEXT NOT NULL
        REFERENCES bottle_identity_version(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    status TEXT NOT NULL CHECK (status IN ('active','inactive')),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE TABLE bottle_identity_version (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    bottle_id TEXT NOT NULL REFERENCES bottle_item(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    version INTEGER NOT NULL CHECK (version >= 1),
    nickname TEXT NOT NULL CHECK (length(CAST(nickname AS BLOB)) BETWEEN 1 AND 512),
    brand TEXT NULL,
    manufacturer TEXT NULL,
    model TEXT NULL,
    capacity_ml INTEGER NULL CHECK (capacity_ml BETWEEN 1 AND 2000),
    material TEXT NULL,
    nipple_spec TEXT NULL,
    gtin TEXT NULL,
    lot_or_serial TEXT NULL,
    manufactured_local_date TEXT NULL CHECK (manufactured_local_date IS NULL OR (
        length(manufactured_local_date) = 10
        AND manufactured_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(manufactured_local_date, '+0 days') IS NOT NULL AND date(manufactured_local_date, '+0 days') = manufactured_local_date)),
    verification_status TEXT NOT NULL CHECK (verification_status IN ('basic','recall_ready')),
    content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    UNIQUE (bottle_id, version)
) STRICT;

CREATE TABLE moment (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    group_local_date TEXT NOT NULL CHECK (
        length(group_local_date) = 10
        AND group_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(group_local_date, '+0 days') IS NOT NULL
        AND date(group_local_date, '+0 days') = group_local_date),
    occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms > 0),
    caption TEXT NULL CHECK (caption IS NULL OR length(CAST(caption AS BLOB)) <= 8192),
    derived_from_moment_id TEXT NULL REFERENCES moment(id) ON DELETE SET NULL,
    grouping_generation INTEGER NOT NULL CHECK (grouping_generation >= 1),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms)
) STRICT;

CREATE INDEX moment_timeline
ON moment(baby_id, group_local_date DESC, deleted_at_ms, occurred_at_ms DESC, created_at_ms DESC, id DESC);

CREATE TABLE media_asset (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL CHECK (purpose IN ('moment','avatar','formula_front','formula_lot','formula_trace','bottle')),
    captured_at_ms INTEGER NULL CHECK (captured_at_ms > 0),
    captured_time_zone TEXT NULL CHECK (captured_time_zone IS NULL OR length(captured_time_zone) BETWEEN 1 AND 64),
    captured_utc_offset_seconds INTEGER NULL CHECK (captured_utc_offset_seconds BETWEEN -64800 AND 64800),
    captured_baby_local_date TEXT NULL CHECK (
        captured_baby_local_date IS NULL OR (
          length(captured_baby_local_date) = 10
          AND captured_baby_local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
          AND date(captured_baby_local_date, '+0 days') IS NOT NULL
          AND date(captured_baby_local_date, '+0 days') = captured_baby_local_date)),
    source_kind TEXT NOT NULL CHECK (source_kind IN ('photos_picker','camera','archive_import')),
    metadata_confidence TEXT NOT NULL CHECK (metadata_confidence IN ('absolute','offset_exif','assumed_timezone','user_confirmed','not_applicable')),
    local_revision INTEGER NOT NULL DEFAULT 1 CHECK (local_revision >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    created_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    updated_by_actor_id TEXT NOT NULL REFERENCES local_actor(id) ON DELETE RESTRICT,
    deleted_at_ms INTEGER NULL CHECK (deleted_at_ms IS NULL OR deleted_at_ms >= created_at_ms),
    CHECK (
      (purpose = 'moment' AND captured_at_ms IS NOT NULL AND captured_time_zone IS NOT NULL
       AND captured_utc_offset_seconds IS NOT NULL AND captured_baby_local_date IS NOT NULL)
      OR purpose <> 'moment'
    ),
    CHECK ((captured_at_ms IS NULL AND captured_time_zone IS NULL AND captured_utc_offset_seconds IS NULL)
        OR (captured_at_ms IS NOT NULL AND captured_time_zone IS NOT NULL AND captured_utc_offset_seconds IS NOT NULL))
) STRICT;

CREATE INDEX media_asset_by_baby_purpose
ON media_asset(baby_id, purpose, deleted_at_ms, captured_at_ms DESC);

CREATE TABLE local_media_replica (
    asset_id TEXT NOT NULL REFERENCES media_asset(id) ON DELETE CASCADE,
    variant TEXT NOT NULL CHECK (variant IN ('display','thumbnail','evidence','avatar')),
    relative_path TEXT NOT NULL UNIQUE
        CHECK (substr(relative_path,1,1) <> '/' AND instr('/' || relative_path || '/', '/../') = 0 AND length(relative_path) <= 512),
    mime_type TEXT NOT NULL CHECK (mime_type IN ('image/heic','image/jpeg','image/png')),
    width_px INTEGER NOT NULL CHECK (width_px BETWEEN 1 AND 20000),
    height_px INTEGER NOT NULL CHECK (height_px BETWEEN 1 AND 20000),
    byte_size INTEGER NOT NULL CHECK (byte_size BETWEEN 1 AND 52428800),
    sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
    state TEXT NOT NULL CHECK (state IN ('ready','missing','quarantined')),
    protection_verified INTEGER NOT NULL CHECK (protection_verified IN (0,1)),
    backup_policy_generation INTEGER NOT NULL CHECK (backup_policy_generation >= 1),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    PRIMARY KEY (asset_id, variant),
    CHECK (width_px * 1.0 * height_px <= 80000000)
) STRICT, WITHOUT ROWID;

CREATE TABLE moment_asset (
    moment_id TEXT NOT NULL REFERENCES moment(id) ON DELETE CASCADE,
    asset_id TEXT NOT NULL UNIQUE REFERENCES media_asset(id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL CHECK (display_order BETWEEN 0 AND 8),
    PRIMARY KEY (moment_id, asset_id),
    UNIQUE (moment_id, display_order)
) STRICT, WITHOUT ROWID;

CREATE TABLE formula_evidence (
    container_version_id TEXT NOT NULL REFERENCES formula_container_version(id) ON DELETE CASCADE,
    asset_id TEXT NOT NULL UNIQUE REFERENCES media_asset(id) ON DELETE CASCADE,
    evidence_type TEXT NOT NULL CHECK (evidence_type IN ('front','lot_date','trace')),
    capture_source TEXT NOT NULL CHECK (capture_source IN ('camera','photos_picker','archive_import')),
    ocr_confidence REAL NULL CHECK (ocr_confidence BETWEEN 0.0 AND 1.0),
    user_confirmed_at_ms INTEGER NULL CHECK (user_confirmed_at_ms > 0),
    PRIMARY KEY (container_version_id, asset_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE bottle_evidence (
    bottle_version_id TEXT NOT NULL REFERENCES bottle_identity_version(id) ON DELETE CASCADE,
    asset_id TEXT NOT NULL UNIQUE REFERENCES media_asset(id) ON DELETE CASCADE,
    evidence_type TEXT NOT NULL CHECK (evidence_type IN ('front','model_lot','code')),
    capture_source TEXT NOT NULL CHECK (capture_source IN ('camera','photos_picker','archive_import')),
    user_confirmed_at_ms INTEGER NULL CHECK (user_confirmed_at_ms > 0),
    PRIMARY KEY (bottle_version_id, asset_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE formula_use (
    feeding_event_id TEXT NOT NULL REFERENCES feeding_detail(event_id) ON DELETE CASCADE,
    container_version_id TEXT NOT NULL REFERENCES formula_container_version(id) ON DELETE RESTRICT,
    contribution_ml INTEGER NULL CHECK (contribution_ml BETWEEN 1 AND 2000),
    contribution_known INTEGER NOT NULL CHECK (contribution_known IN (0,1)),
    PRIMARY KEY (feeding_event_id, container_version_id),
    CHECK ((contribution_known = 1 AND contribution_ml IS NOT NULL)
        OR (contribution_known = 0 AND contribution_ml IS NULL))
) STRICT, WITHOUT ROWID;

CREATE INDEX formula_use_by_container
ON formula_use(container_version_id, feeding_event_id);

CREATE TABLE bottle_use (
    feeding_event_id TEXT PRIMARY KEY REFERENCES feeding_detail(event_id) ON DELETE CASCADE,
    bottle_version_id TEXT NOT NULL REFERENCES bottle_identity_version(id) ON DELETE RESTRICT
) STRICT;

CREATE INDEX bottle_use_by_bottle
ON bottle_use(bottle_version_id, feeding_event_id);

CREATE TABLE media_import_job (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    baby_id TEXT NOT NULL REFERENCES baby_profile(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL CHECK (purpose IN ('moment','avatar','formula_front','formula_lot','formula_trace','bottle')),
    state TEXT NOT NULL CHECK (state IN ('draft','staging','processing','moving','committing','completed','failed','cancelled')),
    desired_action TEXT NOT NULL CHECK (desired_action IN ('continue','retry','cancel')),
    item_count INTEGER NOT NULL CHECK (item_count BETWEEN 1 AND 9),
    form_draft_json TEXT NULL CHECK (form_draft_json IS NULL OR (json_valid(form_draft_json) AND length(CAST(form_draft_json AS BLOB)) <= 65536)),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL CHECK (claim_id IS NULL OR (length(claim_id) = 36 AND claim_id = lower(claim_id))),
    heartbeat_at_ms INTEGER NULL CHECK (heartbeat_at_ms > 0),
    claim_expires_at_ms INTEGER NULL CHECK (claim_expires_at_ms > heartbeat_at_ms),
    error_group TEXT NULL,
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    expires_at_ms INTEGER NOT NULL CHECK (expires_at_ms > created_at_ms),
    CHECK ((claim_id IS NULL AND heartbeat_at_ms IS NULL AND claim_expires_at_ms IS NULL)
        OR (claim_id IS NOT NULL AND heartbeat_at_ms IS NOT NULL AND claim_expires_at_ms IS NOT NULL)),
    CHECK (state NOT IN ('completed','failed','cancelled') OR claim_id IS NULL)
) STRICT;

CREATE INDEX media_import_recovery
ON media_import_job(state, claim_expires_at_ms, updated_at_ms)
WHERE state NOT IN ('completed','failed','cancelled');

CREATE TABLE media_import_item (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    job_id TEXT NOT NULL REFERENCES media_import_job(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL CHECK (ordinal BETWEEN 0 AND 8),
    asset_id TEXT NOT NULL CHECK (length(asset_id) = 36 AND asset_id = lower(asset_id)),
    state TEXT NOT NULL CHECK (state IN ('declared','copied','validated','processed','move_claimed','moved','db_committed','failed','cancelled')),
    source_relative_path TEXT NULL
        CHECK (source_relative_path IS NULL OR (substr(source_relative_path,1,1) <> '/' AND instr('/' || source_relative_path || '/', '/../') = 0 AND length(source_relative_path) <= 512)),
    staging_manifest_json TEXT NULL CHECK (staging_manifest_json IS NULL OR (json_valid(staging_manifest_json) AND length(CAST(staging_manifest_json AS BLOB)) <= 65536)),
    input_byte_size INTEGER NULL CHECK (input_byte_size BETWEEN 1 AND 20971520),
    sniffed_mime_type TEXT NULL CHECK (sniffed_mime_type IN ('image/heic','image/jpeg','image/png')),
    source_sha256 TEXT NULL CHECK (source_sha256 IS NULL OR length(source_sha256) = 64),
    width_px INTEGER NULL CHECK (width_px BETWEEN 1 AND 20000),
    height_px INTEGER NULL CHECK (height_px BETWEEN 1 AND 20000),
    frame_count INTEGER NULL CHECK (frame_count = 1),
    output_manifest_json TEXT NULL CHECK (output_manifest_json IS NULL OR (json_valid(output_manifest_json) AND length(CAST(output_manifest_json AS BLOB)) <= 65536)),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL CHECK (claim_id IS NULL OR (length(claim_id) = 36 AND claim_id = lower(claim_id))),
    heartbeat_at_ms INTEGER NULL CHECK (heartbeat_at_ms > 0),
    claim_expires_at_ms INTEGER NULL CHECK (claim_expires_at_ms > heartbeat_at_ms),
    error_group TEXT NULL,
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    UNIQUE (job_id, ordinal),
    UNIQUE (job_id, asset_id),
    CHECK (width_px IS NULL OR height_px IS NULL OR width_px * 1.0 * height_px <= 80000000),
    CHECK ((claim_id IS NULL AND heartbeat_at_ms IS NULL AND claim_expires_at_ms IS NULL)
        OR (claim_id IS NOT NULL AND heartbeat_at_ms IS NOT NULL AND claim_expires_at_ms IS NOT NULL)),
    CHECK (state NOT IN ('db_committed','failed','cancelled') OR claim_id IS NULL)
) STRICT;

CREATE INDEX media_import_item_claim
ON media_import_item(state, claim_expires_at_ms, heartbeat_at_ms);

CREATE TABLE pending_purge (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('db_hidden','staging_files','undoable','restoring','purging','completed','damaged')),
    desired_action TEXT NOT NULL CHECK (desired_action IN ('delete','restore','purge')),
    state_revision INTEGER NOT NULL DEFAULT 1 CHECK (state_revision >= 1),
    intent_revision INTEGER NOT NULL DEFAULT 1 CHECK (intent_revision >= 1),
    relation_ids_json TEXT NOT NULL CHECK (json_valid(relation_ids_json) AND length(CAST(relation_ids_json AS BLOB)) <= 65536),
    undo_deadline_ms INTEGER NOT NULL CHECK (undo_deadline_ms > 0),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    UNIQUE (entity_type, entity_id)
) STRICT;

CREATE INDEX pending_purge_recovery
ON pending_purge(state, desired_action, updated_at_ms)
WHERE state <> 'completed';

CREATE TABLE pending_purge_file (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    purge_id TEXT NOT NULL REFERENCES pending_purge(id) ON DELETE CASCADE,
    media_asset_id TEXT NULL REFERENCES media_asset(id) ON DELETE SET NULL,
    source_relative_path TEXT NOT NULL
        CHECK (substr(source_relative_path,1,1) <> '/' AND instr('/' || source_relative_path || '/', '/../') = 0 AND length(source_relative_path) <= 512),
    trash_relative_path TEXT NOT NULL UNIQUE
        CHECK (substr(trash_relative_path,1,1) <> '/' AND instr('/' || trash_relative_path || '/', '/../') = 0 AND length(trash_relative_path) <= 512),
    expected_sha256 TEXT NOT NULL CHECK (length(expected_sha256) = 64),
    physical_phase TEXT NOT NULL CHECK (physical_phase IN ('at_source','move_to_trash_claimed','at_trash','restore_claimed','restored','purge_claimed','purged','damaged')),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL,
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms > 0),
    UNIQUE (purge_id, source_relative_path)
) STRICT;

CREATE TABLE migration_journal (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    from_schema_version INTEGER NOT NULL CHECK (from_schema_version >= 1),
    to_schema_version INTEGER NOT NULL CHECK (to_schema_version > from_schema_version),
    from_media_layout_version INTEGER NOT NULL CHECK (from_media_layout_version >= 1),
    to_media_layout_version INTEGER NOT NULL CHECK (to_media_layout_version >= from_media_layout_version),
    state TEXT NOT NULL CHECK (state IN ('prepared','schema_migrating','files_migrating','validating','completed','rolling_back','failed')),
    snapshot_relative_path TEXT NOT NULL
        CHECK (substr(snapshot_relative_path,1,1) <> '/' AND instr('/' || snapshot_relative_path || '/', '/../') = 0 AND length(snapshot_relative_path) <= 512),
    snapshot_sha256 TEXT NOT NULL CHECK (length(snapshot_sha256) = 64),
    required_free_bytes INTEGER NOT NULL CHECK (required_free_bytes > 0),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL,
    error_group TEXT NULL,
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    completed_at_ms INTEGER NULL CHECK (completed_at_ms IS NULL OR completed_at_ms >= created_at_ms)
) STRICT;

CREATE UNIQUE INDEX one_open_migration_per_vault
ON migration_journal(local_vault_id)
WHERE state NOT IN ('completed','failed');

CREATE TABLE migration_file_item (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    migration_id TEXT NOT NULL REFERENCES migration_journal(id) ON DELETE CASCADE,
    source_relative_path TEXT NOT NULL,
    target_relative_path TEXT NOT NULL,
    expected_sha256 TEXT NOT NULL CHECK (length(expected_sha256) = 64),
    state TEXT NOT NULL CHECK (state IN ('pending','move_claimed','moved','verified','rolled_back','failed')),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL,
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms > 0),
    UNIQUE (migration_id, source_relative_path),
    UNIQUE (migration_id, target_relative_path),
    CHECK (substr(source_relative_path,1,1) <> '/' AND instr('/' || source_relative_path || '/', '/../') = 0),
    CHECK (substr(target_relative_path,1,1) <> '/' AND instr('/' || target_relative_path || '/', '/../') = 0)
) STRICT;

CREATE TABLE maintenance_checkpoint (
    task_name TEXT PRIMARY KEY,
    cursor_json TEXT NULL CHECK (cursor_json IS NULL OR json_valid(cursor_json)),
    lease_owner TEXT NULL,
    lease_expires_at_ms INTEGER NULL CHECK (lease_expires_at_ms > 0),
    last_started_at_ms INTEGER NULL CHECK (last_started_at_ms > 0),
    last_completed_at_ms INTEGER NULL CHECK (last_completed_at_ms > 0),
    last_error_group TEXT NULL
) STRICT;

CREATE TABLE archive_export_session (
    id TEXT PRIMARY KEY CHECK (length(id) = 36 AND id = lower(id)),
    local_vault_id TEXT NOT NULL REFERENCES local_vault(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK (state IN (
        'preparing','materializing','awaiting_destination','writing','validating_output',
        'archive_validated_locally','handing_off','external_copy_verified',
        'handoff_completed','failed','cancelled')),
    snapshot_data_revision INTEGER NOT NULL CHECK (snapshot_data_revision >= 0),
    staging_relative_path TEXT NOT NULL
        CHECK (substr(staging_relative_path,1,1) <> '/' AND instr('/' || staging_relative_path || '/', '/../') = 0),
    destination_kind TEXT NOT NULL CHECK (destination_kind IN ('verified_files','share_sheet','finder')),
    manifest_sha256 TEXT NULL CHECK (manifest_sha256 IS NULL OR length(manifest_sha256) = 64),
    emission_epoch INTEGER NOT NULL DEFAULT 0 CHECK (emission_epoch >= 0),
    archive_id TEXT NULL CHECK (archive_id IS NULL OR (length(archive_id) = 36 AND archive_id = lower(archive_id))),
    last_complete_sequence INTEGER NULL CHECK (last_complete_sequence >= 0),
    checkpoint_byte_offset INTEGER NULL CHECK (checkpoint_byte_offset > 0),
    checkpoint_prefix_sha256 TEXT NULL CHECK (checkpoint_prefix_sha256 IS NULL OR length(checkpoint_prefix_sha256) = 64),
    output_sha256 TEXT NULL CHECK (output_sha256 IS NULL OR length(output_sha256) = 64),
    operation_epoch INTEGER NOT NULL DEFAULT 0 CHECK (operation_epoch >= 0),
    claim_id TEXT NULL CHECK (claim_id IS NULL OR (length(claim_id) = 36 AND claim_id = lower(claim_id))),
    heartbeat_at_ms INTEGER NULL CHECK (heartbeat_at_ms > 0),
    claim_expires_at_ms INTEGER NULL CHECK (claim_expires_at_ms > heartbeat_at_ms),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
    completed_at_ms INTEGER NULL CHECK (completed_at_ms IS NULL OR completed_at_ms >= created_at_ms),
    CHECK ((last_complete_sequence IS NULL AND checkpoint_byte_offset IS NULL AND checkpoint_prefix_sha256 IS NULL)
        OR (last_complete_sequence IS NOT NULL AND checkpoint_byte_offset IS NOT NULL
          AND checkpoint_prefix_sha256 IS NOT NULL AND archive_id IS NOT NULL)),
    CHECK (state NOT IN ('writing','validating_output','archive_validated_locally','handing_off',
          'external_copy_verified','handoff_completed') OR archive_id IS NOT NULL),
    CHECK (state NOT IN ('archive_validated_locally','handing_off','external_copy_verified','handoff_completed')
        OR output_sha256 IS NOT NULL),
    CHECK ((claim_id IS NULL AND heartbeat_at_ms IS NULL AND claim_expires_at_ms IS NULL)
        OR (claim_id IS NOT NULL AND heartbeat_at_ms IS NOT NULL AND claim_expires_at_ms IS NOT NULL)),
    CHECK (state NOT IN ('external_copy_verified','handoff_completed','failed','cancelled') OR claim_id IS NULL),
    CHECK ((state IN ('external_copy_verified','handoff_completed','failed','cancelled') AND completed_at_ms IS NOT NULL)
        OR (state NOT IN ('external_copy_verified','handoff_completed','failed','cancelled') AND completed_at_ms IS NULL))
) STRICT;

CREATE UNIQUE INDEX one_open_archive_export_per_vault
ON archive_export_session(local_vault_id)
WHERE state NOT IN ('external_copy_verified','handoff_completed','failed','cancelled');

CREATE TABLE archive_media_pin (
    export_session_id TEXT NOT NULL REFERENCES archive_export_session(id) ON DELETE CASCADE,
    asset_id TEXT NOT NULL REFERENCES media_asset(id) ON DELETE RESTRICT,
    variant TEXT NOT NULL CHECK (variant IN ('display','evidence','avatar')),
    expected_sha256 TEXT NOT NULL CHECK (length(expected_sha256) = 64),
    created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
    PRIMARY KEY (export_session_id, asset_id, variant),
    FOREIGN KEY (asset_id, variant)
        REFERENCES local_media_replica(asset_id, variant) ON DELETE RESTRICT
) STRICT, WITHOUT ROWID;

CREATE TRIGGER archive_pin_matches_ready_replica
BEFORE INSERT ON archive_media_pin BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM local_media_replica r
    WHERE r.asset_id = NEW.asset_id AND r.variant = NEW.variant
      AND r.state = 'ready' AND r.protection_verified = 1
      AND r.sha256 = NEW.expected_sha256
  ) THEN RAISE(ABORT, 'archive pin requires matching ready protected replica') END;
END;

CREATE TRIGGER archive_pin_is_immutable
BEFORE UPDATE ON archive_media_pin BEGIN
  SELECT RAISE(ABORT, 'archive pin is immutable');
END;

CREATE TRIGGER pinned_replica_is_immutable
BEFORE UPDATE ON local_media_replica
WHEN EXISTS (
  SELECT 1 FROM archive_media_pin p
  WHERE p.asset_id = OLD.asset_id AND p.variant = OLD.variant
) BEGIN
  SELECT RAISE(ABORT, 'pinned media replica cannot change');
END;

CREATE TRIGGER baby_requires_matching_consent_insert
BEFORE INSERT ON baby_profile BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM consent_record c
    WHERE c.id = NEW.current_consent_id AND c.subject_type = 'child'
      AND c.baby_id = NEW.id AND c.local_vault_id = NEW.local_vault_id
      AND c.withdrawn_at_ms IS NULL
  ) THEN RAISE(ABORT, 'baby consent mismatch') END;
END;

CREATE TRIGGER baby_requires_matching_consent_update
BEFORE UPDATE OF current_consent_id ON baby_profile BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM consent_record c
    WHERE c.id = NEW.current_consent_id AND c.subject_type = 'child'
      AND c.baby_id = NEW.id AND c.local_vault_id = NEW.local_vault_id
      AND c.withdrawn_at_ms IS NULL
  ) THEN RAISE(ABORT, 'baby consent mismatch') END;
END;

CREATE TRIGGER adult_requires_matching_consent_insert
BEFORE INSERT ON lactating_profile BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM consent_record c
    WHERE c.id = NEW.current_consent_id AND c.subject_type = 'adult'
      AND c.lactating_profile_id = NEW.id AND c.local_vault_id = NEW.local_vault_id
      AND c.adult_actor_id = NEW.owner_actor_id AND c.withdrawn_at_ms IS NULL
  ) THEN RAISE(ABORT, 'adult consent mismatch') END;
END;

CREATE TRIGGER adult_requires_matching_consent_update
BEFORE UPDATE OF current_consent_id ON lactating_profile BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM consent_record c
    WHERE c.id = NEW.current_consent_id AND c.subject_type = 'adult'
      AND c.lactating_profile_id = NEW.id AND c.local_vault_id = NEW.local_vault_id
      AND c.adult_actor_id = NEW.owner_actor_id AND c.withdrawn_at_ms IS NULL
  ) THEN RAISE(ABORT, 'adult consent mismatch') END;
END;

-- Consent evidence is append-only. Re-consent creates a new row and switches
-- the profile pointer; withdrawal is the sole monotonic mutation on an old row.
CREATE TRIGGER consent_evidence_is_immutable
BEFORE UPDATE OF id, local_vault_id, subject_type, baby_id, lactating_profile_id,
  guardian_actor_id, adult_actor_id, policy_version, scope_json, notice_sha256,
  granted_at_ms ON consent_record
WHEN NEW.id IS NOT OLD.id
  OR NEW.local_vault_id IS NOT OLD.local_vault_id
  OR NEW.subject_type IS NOT OLD.subject_type
  OR NEW.baby_id IS NOT OLD.baby_id
  OR NEW.lactating_profile_id IS NOT OLD.lactating_profile_id
  OR NEW.guardian_actor_id IS NOT OLD.guardian_actor_id
  OR NEW.adult_actor_id IS NOT OLD.adult_actor_id
  OR NEW.policy_version IS NOT OLD.policy_version
  OR NEW.scope_json IS NOT OLD.scope_json
  OR NEW.notice_sha256 IS NOT OLD.notice_sha256
  OR NEW.granted_at_ms IS NOT OLD.granted_at_ms BEGIN
  SELECT RAISE(ABORT, 'consent evidence is immutable');
END;

-- Consent history can disappear only as part of deleting its data subject.
-- During an FK cascade the parent row is already absent, so subject deletion
-- remains valid while direct deletion of current or historical evidence fails.
CREATE TRIGGER consent_delete_requires_subject_deletion
BEFORE DELETE ON consent_record
WHEN (OLD.subject_type = 'child' AND EXISTS (
        SELECT 1 FROM baby_profile b WHERE b.id = OLD.baby_id
      ))
   OR (OLD.subject_type = 'adult' AND EXISTS (
        SELECT 1 FROM lactating_profile p WHERE p.id = OLD.lactating_profile_id
      ))
BEGIN
  SELECT RAISE(ABORT, 'delete consent only with its subject');
END;

-- The coordinator must converge timers and detach adult-child edges before
-- changing the current grant. This trigger prevents direct-SQL bypass.
CREATE TRIGGER consent_withdrawal_requires_quiescence
BEFORE UPDATE OF withdrawn_at_ms ON consent_record
WHEN OLD.withdrawn_at_ms IS NULL AND NEW.withdrawn_at_ms IS NOT NULL
BEGIN
  SELECT CASE WHEN NOT (
    (OLD.subject_type = 'child' AND EXISTS (
      SELECT 1 FROM baby_profile b
      WHERE b.id = OLD.baby_id AND b.current_consent_id = OLD.id
    )) OR
    (OLD.subject_type = 'adult' AND EXISTS (
      SELECT 1 FROM lactating_profile p
      WHERE p.id = OLD.lactating_profile_id AND p.current_consent_id = OLD.id
    ))
  ) THEN RAISE(ABORT, 'only current consent can be withdrawn') END;

  SELECT CASE WHEN
    (OLD.subject_type = 'child' AND EXISTS (
      SELECT 1 FROM timer_session s
      WHERE s.baby_id = OLD.baby_id
        AND s.state NOT IN ('finished','abandoned')
    )) OR
    (OLD.subject_type = 'adult' AND EXISTS (
      SELECT 1 FROM timer_session s
      WHERE s.lactating_profile_id = OLD.lactating_profile_id
        AND s.state NOT IN ('finished','abandoned')
    ))
  THEN RAISE(ABORT, 'settle active timer before consent withdrawal') END;

  SELECT CASE WHEN
    (OLD.subject_type = 'child' AND (
      EXISTS (SELECT 1 FROM timer_session s
              WHERE s.baby_id = OLD.baby_id
                AND s.lactating_profile_id IS NOT NULL)
      OR EXISTS (SELECT 1 FROM nursing_side_detail d
                 JOIN care_event e ON e.id = d.related_event_id
                 WHERE e.baby_id = OLD.baby_id)
      OR EXISTS (SELECT 1 FROM pumping_record r
                 WHERE r.related_baby_id = OLD.baby_id)
      OR EXISTS (SELECT 1 FROM care_event e
                 JOIN timer_session s ON s.id = e.source_timer_session_id
                 WHERE e.baby_id = OLD.baby_id
                   AND s.lactating_profile_id IS NOT NULL)
    )) OR
    (OLD.subject_type = 'adult' AND (
      EXISTS (SELECT 1 FROM timer_session s
              WHERE s.lactating_profile_id = OLD.lactating_profile_id
                AND s.baby_id IS NOT NULL)
      OR EXISTS (SELECT 1 FROM nursing_side_detail d
                 WHERE d.lactating_profile_id = OLD.lactating_profile_id
                   AND d.related_event_id IS NOT NULL)
      OR EXISTS (SELECT 1 FROM pumping_record r
                 WHERE r.lactating_profile_id = OLD.lactating_profile_id
                   AND r.related_baby_id IS NOT NULL)
      OR EXISTS (SELECT 1 FROM care_event e
                 JOIN timer_session s ON s.id = e.source_timer_session_id
                 WHERE s.lactating_profile_id = OLD.lactating_profile_id)
    ))
  THEN RAISE(ABORT, 'detach adult-child relations before consent withdrawal') END;
END;

CREATE TRIGGER consent_withdrawal_is_monotonic
BEFORE UPDATE OF withdrawn_at_ms ON consent_record
WHEN OLD.withdrawn_at_ms IS NOT NULL
 AND NEW.withdrawn_at_ms IS NOT OLD.withdrawn_at_ms BEGIN
  SELECT RAISE(ABORT, 'consent withdrawal cannot be changed or cleared');
END;

CREATE TRIGGER baby_profile_identity_is_immutable
BEFORE UPDATE OF id, local_vault_id ON baby_profile
WHEN NEW.id IS NOT OLD.id OR NEW.local_vault_id IS NOT OLD.local_vault_id BEGIN
  SELECT RAISE(ABORT, 'baby profile identity is immutable');
END;

CREATE TRIGGER lactating_profile_identity_is_immutable
BEFORE UPDATE OF id, local_vault_id, owner_actor_id ON lactating_profile
WHEN NEW.id IS NOT OLD.id OR NEW.local_vault_id IS NOT OLD.local_vault_id
  OR NEW.owner_actor_id IS NOT OLD.owner_actor_id BEGIN
  SELECT RAISE(ABORT, 'lactating profile identity is immutable');
END;

CREATE TRIGGER care_type_is_immutable
BEFORE UPDATE OF id, type, baby_id ON care_event
WHEN NEW.id IS NOT OLD.id OR NEW.type IS NOT OLD.type OR NEW.baby_id IS NOT OLD.baby_id BEGIN
  SELECT RAISE(ABORT, 'care event type and owner are immutable');
END;

CREATE TRIGGER care_timer_source_validate_insert
BEFORE INSERT ON care_event
WHEN NEW.source_timer_session_id IS NOT NULL BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s
    WHERE s.id = NEW.source_timer_session_id AND s.baby_id = NEW.baby_id
      AND s.state NOT IN ('finished','abandoned')
      AND ((NEW.type = 'nursing' AND s.type = 'nursing')
        OR (NEW.type = 'sleep' AND s.type = 'sleep'))
  ) THEN RAISE(ABORT, 'care event timer source mismatch') END;
END;

CREATE TRIGGER care_timer_source_is_one_way
BEFORE UPDATE OF source_timer_session_id ON care_event
WHEN NOT (
  NEW.source_timer_session_id IS OLD.source_timer_session_id
  OR (OLD.source_timer_session_id IS NOT NULL AND NEW.source_timer_session_id IS NULL)
) BEGIN
  SELECT RAISE(ABORT, 'care event timer source can only be detached');
END;

CREATE TRIGGER feeding_matches_parent_insert
BEFORE INSERT ON feeding_detail BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.event_id
      AND ((NEW.mode = 'nursing' AND e.type = 'nursing')
        OR (NEW.mode = 'bottle' AND e.type = 'bottle'))
  ) THEN RAISE(ABORT, 'feeding parent mismatch') END;
END;

CREATE TRIGGER feeding_matches_parent_update
BEFORE UPDATE ON feeding_detail BEGIN
  SELECT CASE WHEN NEW.event_id IS NOT OLD.event_id
    THEN RAISE(ABORT, 'feeding parent is immutable') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.event_id
      AND ((NEW.mode = 'nursing' AND e.type = 'nursing')
        OR (NEW.mode = 'bottle' AND e.type = 'bottle'))
  ) THEN RAISE(ABORT, 'feeding parent mismatch') END;
END;

CREATE TRIGGER feeding_use_reverse_update
BEFORE UPDATE OF mode, milk_type ON feeding_detail BEGIN
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM formula_use u WHERE u.feeding_event_id = NEW.event_id
  ) AND NOT (NEW.mode = 'bottle' AND NEW.milk_type = 'formula')
    THEN RAISE(ABORT, 'detach formula use before changing feeding kind') END;
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM bottle_use u WHERE u.feeding_event_id = NEW.event_id
  ) AND NEW.mode <> 'bottle'
    THEN RAISE(ABORT, 'detach bottle use before changing feeding kind') END;
END;

CREATE TRIGGER diaper_matches_parent_insert
BEFORE INSERT ON diaper_detail BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.event_id AND e.type = 'diaper'
  ) THEN RAISE(ABORT, 'diaper parent mismatch') END;
END;

CREATE TRIGGER diaper_matches_parent_update
BEFORE UPDATE ON diaper_detail BEGIN
  SELECT CASE WHEN NEW.event_id IS NOT OLD.event_id
    THEN RAISE(ABORT, 'diaper parent is immutable') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.event_id AND e.type = 'diaper'
  ) THEN RAISE(ABORT, 'diaper parent mismatch') END;
END;

CREATE TRIGGER care_not_before_birth_insert
BEFORE INSERT ON care_event BEGIN
  SELECT CASE WHEN NEW.group_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'care event before birth') END;
END;
CREATE TRIGGER care_not_before_birth_update
BEFORE UPDATE OF baby_id, group_local_date ON care_event BEGIN
  SELECT CASE WHEN NEW.group_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'care event before birth') END;
END;

CREATE TRIGGER growth_not_before_birth_insert
BEFORE INSERT ON growth_record BEGIN
  SELECT CASE WHEN NEW.measured_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'growth before birth') END;
END;
CREATE TRIGGER growth_not_before_birth_update
BEFORE UPDATE OF baby_id, measured_local_date ON growth_record BEGIN
  SELECT CASE WHEN NEW.measured_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'growth before birth') END;
END;

CREATE TRIGGER moment_not_before_birth_insert
BEFORE INSERT ON moment BEGIN
  SELECT CASE WHEN NEW.group_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'moment before birth') END;
END;
CREATE TRIGGER moment_not_before_birth_update
BEFORE UPDATE OF baby_id, group_local_date ON moment BEGIN
  SELECT CASE WHEN NEW.group_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.baby_id)
    THEN RAISE(ABORT, 'moment before birth') END;
END;

CREATE TRIGGER pumping_relation_not_before_birth_insert
BEFORE INSERT ON pumping_record
WHEN NEW.related_baby_id IS NOT NULL BEGIN
  SELECT CASE WHEN NEW.related_baby_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.related_baby_id)
    THEN RAISE(ABORT, 'related pumping before birth') END;
END;
CREATE TRIGGER pumping_relation_not_before_birth_update
BEFORE UPDATE OF related_baby_id, related_baby_local_date ON pumping_record
WHEN NEW.related_baby_id IS NOT NULL BEGIN
  SELECT CASE WHEN NEW.related_baby_local_date < (SELECT birth_local_date FROM baby_profile WHERE id = NEW.related_baby_id)
    THEN RAISE(ABORT, 'related pumping before birth') END;
END;

CREATE TRIGGER birth_change_preserves_all_facts
BEFORE UPDATE OF birth_local_date ON baby_profile BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM care_event WHERE baby_id = NEW.id AND group_local_date < NEW.birth_local_date)
    OR EXISTS (SELECT 1 FROM growth_record WHERE baby_id = NEW.id AND measured_local_date < NEW.birth_local_date)
    OR EXISTS (SELECT 1 FROM moment WHERE baby_id = NEW.id AND group_local_date < NEW.birth_local_date)
    OR EXISTS (SELECT 1 FROM pumping_record WHERE related_baby_id = NEW.id AND related_baby_local_date < NEW.birth_local_date)
    THEN RAISE(ABORT, 'birth date conflicts with facts') END;
END;

CREATE TRIGGER prevent_new_baby_during_pending_delete
BEFORE INSERT ON baby_profile
WHEN EXISTS (
  SELECT 1 FROM pending_purge p
  WHERE p.entity_type = 'baby_profile' AND p.state <> 'completed'
) BEGIN
  SELECT RAISE(ABORT, 'baby deletion still undoable or purging');
END;

-- Runtime backfill, migrations and archive restore all build the complete child
-- graph first, then enter a terminal state through the validated UPDATE path.
CREATE TRIGGER timer_session_cannot_insert_terminal
BEFORE INSERT ON timer_session
WHEN NEW.state IN ('finished','abandoned') BEGIN
  SELECT RAISE(ABORT, 'terminal timer session must be finalized through update');
END;

CREATE TRIGGER timer_channel_matches_session_insert
BEFORE INSERT ON timer_channel BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.session_id
      AND s.state NOT IN ('finished','abandoned')
      AND ((s.type IN ('nursing','pumping') AND NEW.channel IN ('left','right'))
        OR (s.type = 'sleep' AND NEW.channel = 'generic'))
  ) THEN RAISE(ABORT, 'timer channel/session mismatch') END;
END;
CREATE TRIGGER timer_channel_matches_session_update
BEFORE UPDATE OF session_id, channel ON timer_channel BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.session_id
      AND ((s.type IN ('nursing','pumping') AND NEW.channel IN ('left','right'))
        OR (s.type = 'sleep' AND NEW.channel = 'generic'))
  ) THEN RAISE(ABORT, 'timer channel/session mismatch') END;
END;

-- A session's ownership/type tuple is immutable except for the one-way unlink
-- performed while deleting a baby. Unlinking never permits reassignment.
CREATE TRIGGER timer_session_identity_is_immutable
BEFORE UPDATE OF type, baby_id, baby_context_detached_at_ms, lactating_profile_id ON timer_session
WHEN NOT (
  NEW.type IS OLD.type
  AND NEW.lactating_profile_id IS OLD.lactating_profile_id
  AND (
    (NEW.baby_id IS OLD.baby_id
      AND NEW.baby_context_detached_at_ms IS OLD.baby_context_detached_at_ms)
    OR
    (OLD.baby_id IS NOT NULL AND OLD.baby_context_detached_at_ms IS NULL
      AND NEW.baby_id IS NULL AND NEW.baby_context_detached_at_ms IS NOT NULL
      AND NEW.type IN ('nursing','pumping')
      AND NEW.state IN ('finished','abandoned'))
  )
) BEGIN
  SELECT RAISE(ABORT, 'timer session identity is immutable');
END;

CREATE TRIGGER timer_session_state_transition
BEFORE UPDATE OF state ON timer_session
WHEN NEW.state IS NOT OLD.state AND NOT (
  (OLD.state = 'ready' AND NEW.state IN ('running','abandoned'))
  OR (OLD.state = 'running' AND NEW.state IN ('paused','waiting_for_side','finalizing','finished','abandoned'))
  OR (OLD.state = 'paused' AND NEW.state IN ('running','waiting_for_side','finalizing','finished','abandoned'))
  OR (OLD.state = 'waiting_for_side' AND NEW.state IN ('running','paused','finalizing','finished','abandoned'))
  OR (OLD.state = 'finalizing' AND NEW.state IN ('running','paused','waiting_for_side','finished','abandoned'))
) BEGIN
  SELECT RAISE(ABORT, 'illegal timer session state transition');
END;

-- Terminal state and final record identity cannot be reopened/repointed. Time
-- values may still be corrected by the repository together with all projections.
CREATE TRIGGER terminal_timer_identity_is_immutable
BEFORE UPDATE OF selected_mode, start_command_id, finish_command_id,
  final_care_event_id, final_pumping_record_id ON timer_session
WHEN OLD.state IN ('finished','abandoned') AND NOT (
  OLD.state = 'finished' AND OLD.type = 'nursing'
  AND OLD.baby_id IS NOT NULL AND OLD.baby_context_detached_at_ms IS NULL
  AND OLD.final_care_event_id IS NOT NULL
  AND NEW.selected_mode IS OLD.selected_mode
  AND NEW.start_command_id IS OLD.start_command_id
  AND NEW.finish_command_id IS OLD.finish_command_id
  AND NEW.baby_id IS NULL AND NEW.baby_context_detached_at_ms IS NOT NULL
  AND NEW.final_care_event_id IS NULL
  AND NEW.final_pumping_record_id IS OLD.final_pumping_record_id
) BEGIN
  SELECT RAISE(ABORT, 'terminal timer facts are immutable');
END;

CREATE TRIGGER timer_channel_identity_is_immutable
BEFORE UPDATE OF session_id, channel, is_selected ON timer_channel
WHEN NEW.session_id IS NOT OLD.session_id OR NEW.channel IS NOT OLD.channel
  OR NEW.is_selected IS NOT OLD.is_selected BEGIN
  SELECT RAISE(ABORT, 'timer channel identity is immutable');
END;

CREATE TRIGGER timer_channel_state_transition
BEFORE UPDATE OF state ON timer_channel
WHEN NEW.state IS NOT OLD.state AND NOT (
  (OLD.state = 'not_started' AND NEW.state IN ('running','abandoned'))
  OR (OLD.state = 'running' AND NEW.state IN ('paused','ended','abandoned'))
  OR (OLD.state = 'paused' AND NEW.state IN ('running','ended','abandoned'))
) BEGIN
  SELECT RAISE(ABORT, 'illegal timer channel state transition');
END;

CREATE TRIGGER timer_segment_parent_is_active_insert
BEFORE INSERT ON timer_segment
WHEN NEW.ended_at_ms IS NULL AND NOT EXISTS (
  SELECT 1 FROM timer_channel c JOIN timer_session s ON s.id = c.session_id
  WHERE c.id = NEW.channel_id AND s.state NOT IN ('finished','abandoned')
) BEGIN
  SELECT RAISE(ABORT, 'cannot add open segment to terminal session');
END;

CREATE TRIGGER timer_segment_identity_is_immutable
BEFORE UPDATE OF channel_id, start_command_id ON timer_segment
WHEN NEW.channel_id IS NOT OLD.channel_id OR NEW.start_command_id IS NOT OLD.start_command_id BEGIN
  SELECT RAISE(ABORT, 'timer segment identity is immutable');
END;

CREATE TRIGGER closed_timer_segment_cannot_reopen
BEFORE UPDATE OF ended_at_ms, end_command_id ON timer_segment
WHEN OLD.ended_at_ms IS NOT NULL AND (
  NEW.ended_at_ms IS NULL OR NEW.end_command_id IS NOT OLD.end_command_id
) BEGIN
  SELECT RAISE(ABORT, 'closed timer segment cannot reopen');
END;

CREATE TRIGGER segment_no_overlap_insert
BEFORE INSERT ON timer_segment
WHEN EXISTS (
  SELECT 1 FROM timer_segment x WHERE x.channel_id = NEW.channel_id
    AND NEW.started_at_ms < ifnull(x.ended_at_ms, 9223372036854775807)
    AND x.started_at_ms < ifnull(NEW.ended_at_ms, 9223372036854775807)
) BEGIN
  SELECT RAISE(ABORT, 'timer segments overlap');
END;

CREATE TRIGGER segment_no_overlap_update
BEFORE UPDATE OF channel_id, started_at_ms, ended_at_ms ON timer_segment
WHEN EXISTS (
  SELECT 1 FROM timer_segment x WHERE x.channel_id = NEW.channel_id AND x.id <> OLD.id
    AND NEW.started_at_ms < ifnull(x.ended_at_ms, 9223372036854775807)
    AND x.started_at_ms < ifnull(NEW.ended_at_ms, 9223372036854775807)
) BEGIN
  SELECT RAISE(ABORT, 'timer segments overlap');
END;

CREATE TRIGGER one_open_segment_per_adult_side_insert
BEFORE INSERT ON timer_segment
WHEN NEW.ended_at_ms IS NULL AND EXISTS (
  SELECT 1
  FROM timer_channel nc
  JOIN timer_session ns ON ns.id = nc.session_id
  JOIN timer_segment os ON os.ended_at_ms IS NULL
  JOIN timer_channel oc ON oc.id = os.channel_id
  JOIN timer_session ots ON ots.id = oc.session_id
  WHERE nc.id = NEW.channel_id AND nc.channel IN ('left','right')
    AND ns.lactating_profile_id IS NOT NULL
    AND oc.channel = nc.channel
    AND ots.lactating_profile_id = ns.lactating_profile_id
) BEGIN
  SELECT RAISE(ABORT, 'adult side already has open segment');
END;

CREATE TRIGGER one_open_segment_per_adult_side_update
BEFORE UPDATE OF channel_id, ended_at_ms ON timer_segment
WHEN NEW.ended_at_ms IS NULL AND EXISTS (
  SELECT 1
  FROM timer_channel nc
  JOIN timer_session ns ON ns.id = nc.session_id
  JOIN timer_segment os ON os.ended_at_ms IS NULL AND os.id <> OLD.id
  JOIN timer_channel oc ON oc.id = os.channel_id
  JOIN timer_session ots ON ots.id = oc.session_id
  WHERE nc.id = NEW.channel_id AND nc.channel IN ('left','right')
    AND ns.lactating_profile_id IS NOT NULL
    AND oc.channel = nc.channel
    AND ots.lactating_profile_id = ns.lactating_profile_id
) BEGIN
  SELECT RAISE(ABORT, 'adult side already has open segment');
END;

CREATE TRIGGER active_lock_shape_matches_session
BEFORE INSERT ON active_resource_lock BEGIN
  SELECT CASE WHEN NOT (
    (NEW.lock_kind = 'baby_nursing' AND EXISTS (
      SELECT 1 FROM timer_session s WHERE s.id = NEW.session_id AND s.type = 'nursing'
        AND s.baby_id = NEW.baby_id AND s.state IN ('ready','running','paused','waiting_for_side','finalizing')))
    OR (NEW.lock_kind = 'baby_sleep' AND EXISTS (
      SELECT 1 FROM timer_session s WHERE s.id = NEW.session_id AND s.type = 'sleep'
        AND s.baby_id = NEW.baby_id AND s.state IN ('ready','running','paused','finalizing')))
    OR (NEW.lock_kind = 'adult_pumping' AND EXISTS (
      SELECT 1 FROM timer_session s WHERE s.id = NEW.session_id AND s.type = 'pumping'
        AND s.lactating_profile_id = NEW.lactating_profile_id
        AND s.state IN ('ready','running','paused','waiting_for_side','finalizing')))
    OR (NEW.lock_kind = 'adult_side' AND EXISTS (
      SELECT 1 FROM timer_session s
      JOIN timer_channel c ON c.session_id = s.id
      JOIN timer_segment g ON g.channel_id = c.id AND g.ended_at_ms IS NULL
      WHERE s.id = NEW.session_id AND s.type IN ('nursing','pumping')
        AND s.lactating_profile_id = NEW.lactating_profile_id
        AND c.id = NEW.channel_id AND c.channel = NEW.side AND c.state = 'running'))
  ) THEN RAISE(ABORT, 'active lock owner/slot/session mismatch') END;
END;

CREATE TRIGGER active_lock_is_immutable
BEFORE UPDATE ON active_resource_lock BEGIN
  SELECT RAISE(ABORT, 'delete and reacquire active lock');
END;

CREATE TRIGGER terminal_session_has_no_locks
BEFORE UPDATE OF state ON timer_session
WHEN NEW.state IN ('finished','abandoned')
 AND EXISTS (SELECT 1 FROM active_resource_lock WHERE session_id = NEW.id) BEGIN
  SELECT RAISE(ABORT, 'release locks before terminal state');
END;

CREATE TRIGGER terminal_session_has_closed_channels
BEFORE UPDATE OF state ON timer_session
WHEN NEW.state IN ('finished','abandoned') AND (
  EXISTS (
    SELECT 1 FROM timer_channel c WHERE c.session_id = NEW.id
      AND c.state NOT IN ('ended','abandoned')
  ) OR EXISTS (
    SELECT 1 FROM timer_segment g JOIN timer_channel c ON c.id = g.channel_id
    WHERE c.session_id = NEW.id AND g.ended_at_ms IS NULL
  )
) BEGIN
  SELECT RAISE(ABORT, 'close channels and segments before terminal state');
END;

CREATE TRIGGER finished_session_has_matching_record
BEFORE UPDATE OF state, final_care_event_id, final_pumping_record_id ON timer_session
WHEN NEW.state = 'finished' BEGIN
  SELECT CASE WHEN NEW.type = 'sleep' AND NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.final_care_event_id
      AND e.source_timer_session_id = NEW.id AND e.baby_id = NEW.baby_id
      AND e.type = 'sleep'
  ) THEN RAISE(ABORT, 'finished care record mismatch') END;
  SELECT CASE WHEN NEW.type = 'nursing' AND NEW.baby_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.final_care_event_id
      AND e.source_timer_session_id = NEW.id AND e.baby_id = NEW.baby_id
      AND e.type = 'nursing'
  ) THEN RAISE(ABORT, 'finished nursing care record mismatch') END;
  SELECT CASE WHEN NEW.type = 'nursing' AND NOT EXISTS (
    SELECT 1 FROM nursing_side_detail d WHERE d.timer_session_id = NEW.id
      AND d.lactating_profile_id = NEW.lactating_profile_id
  ) THEN RAISE(ABORT, 'finished nursing adult record mismatch') END;
  SELECT CASE WHEN NEW.type = 'pumping' AND NOT EXISTS (
    SELECT 1 FROM pumping_record p WHERE p.id = NEW.final_pumping_record_id
      AND p.timer_session_id = NEW.id AND p.lactating_profile_id = NEW.lactating_profile_id
      AND p.related_baby_id IS NEW.baby_id
  ) THEN RAISE(ABORT, 'finished pumping record mismatch') END;
END;

CREATE TRIGGER nursing_detail_matches_session_insert
BEFORE INSERT ON nursing_side_detail BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.timer_session_id
      AND s.type = 'nursing' AND s.lactating_profile_id = NEW.lactating_profile_id
  ) THEN RAISE(ABORT, 'nursing detail/session mismatch') END;
  SELECT CASE WHEN NEW.related_event_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.related_event_id
      AND e.type = 'nursing' AND e.source_timer_session_id = NEW.timer_session_id
  ) THEN RAISE(ABORT, 'nursing detail/event mismatch') END;
END;

CREATE TRIGGER nursing_detail_matches_session_update
BEFORE UPDATE OF related_event_id, lactating_profile_id, timer_session_id ON nursing_side_detail BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.timer_session_id
      AND s.type = 'nursing' AND s.lactating_profile_id = NEW.lactating_profile_id
  ) THEN RAISE(ABORT, 'nursing detail/session mismatch') END;
  SELECT CASE WHEN NEW.related_event_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM care_event e WHERE e.id = NEW.related_event_id
      AND e.type = 'nursing' AND e.source_timer_session_id = NEW.timer_session_id
  ) THEN RAISE(ABORT, 'nursing detail/event mismatch') END;
END;

CREATE TRIGGER nursing_detail_relation_is_one_way
BEFORE UPDATE OF related_event_id, lactating_profile_id, timer_session_id ON nursing_side_detail
WHEN NEW.lactating_profile_id IS NOT OLD.lactating_profile_id
  OR NEW.timer_session_id IS NOT OLD.timer_session_id
  OR NOT (
    NEW.related_event_id IS OLD.related_event_id
    OR (OLD.related_event_id IS NOT NULL AND NEW.related_event_id IS NULL)
  ) BEGIN
  SELECT RAISE(ABORT, 'nursing relation can only be detached');
END;

CREATE TRIGGER pumping_matches_session_insert
BEFORE INSERT ON pumping_record BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.timer_session_id
      AND s.type = 'pumping' AND s.lactating_profile_id = NEW.lactating_profile_id
      AND s.baby_id IS NEW.related_baby_id
  ) THEN RAISE(ABORT, 'pumping/session mismatch') END;
END;

CREATE TRIGGER pumping_matches_session_update
BEFORE UPDATE OF timer_session_id, lactating_profile_id, related_baby_id ON pumping_record BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM timer_session s WHERE s.id = NEW.timer_session_id
      AND s.type = 'pumping' AND s.lactating_profile_id = NEW.lactating_profile_id
      AND s.baby_id IS NEW.related_baby_id
  ) THEN RAISE(ABORT, 'pumping/session mismatch') END;
END;

CREATE TRIGGER pumping_relation_is_one_way
BEFORE UPDATE OF timer_session_id, lactating_profile_id, related_baby_id ON pumping_record
WHEN NEW.timer_session_id IS NOT OLD.timer_session_id
  OR NEW.lactating_profile_id IS NOT OLD.lactating_profile_id
  OR NOT (
    NEW.related_baby_id IS OLD.related_baby_id
    OR (OLD.related_baby_id IS NOT NULL AND NEW.related_baby_id IS NULL)
  ) BEGIN
  SELECT RAISE(ABORT, 'pumping relation can only be detached');
END;

CREATE TRIGGER formula_product_current_matches_insert
BEFORE INSERT ON formula_product BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM formula_product_version v WHERE v.id = NEW.current_version_id AND v.product_id = NEW.id
  ) THEN RAISE(ABORT, 'formula product current version mismatch') END;
END;
CREATE TRIGGER formula_product_current_matches_update
BEFORE UPDATE OF current_version_id ON formula_product BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM formula_product_version v WHERE v.id = NEW.current_version_id AND v.product_id = NEW.id
  ) THEN RAISE(ABORT, 'formula product current version mismatch') END;
END;

CREATE TRIGGER formula_container_current_matches_insert
BEFORE INSERT ON formula_container BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM formula_container_version cv
    JOIN formula_product_version pv ON pv.id = cv.product_version_id
    WHERE cv.id = NEW.current_version_id AND cv.container_id = NEW.id AND pv.product_id = NEW.product_id
  ) THEN RAISE(ABORT, 'formula container current version mismatch') END;
END;
CREATE TRIGGER formula_container_current_matches_update
BEFORE UPDATE OF current_version_id ON formula_container BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM formula_container_version cv
    JOIN formula_product_version pv ON pv.id = cv.product_version_id
    WHERE cv.id = NEW.current_version_id AND cv.container_id = NEW.id AND pv.product_id = NEW.product_id
  ) THEN RAISE(ABORT, 'formula container current version mismatch') END;
END;

CREATE TRIGGER bottle_current_matches_insert
BEFORE INSERT ON bottle_item BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM bottle_identity_version v WHERE v.id = NEW.current_version_id AND v.bottle_id = NEW.id
  ) THEN RAISE(ABORT, 'bottle current version mismatch') END;
END;
CREATE TRIGGER bottle_current_matches_update
BEFORE UPDATE OF current_version_id ON bottle_item BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM bottle_identity_version v WHERE v.id = NEW.current_version_id AND v.bottle_id = NEW.id
  ) THEN RAISE(ABORT, 'bottle current version mismatch') END;
END;

-- Ownership and media purpose are identity. Moving an object across a baby,
-- product or purpose creates a new entity/version instead of mutating links.
CREATE TRIGGER formula_product_owner_is_immutable
BEFORE UPDATE OF baby_id ON formula_product
WHEN NEW.baby_id IS NOT OLD.baby_id BEGIN
  SELECT RAISE(ABORT, 'formula product owner is immutable');
END;

CREATE TRIGGER formula_container_product_is_immutable
BEFORE UPDATE OF product_id ON formula_container
WHEN NEW.product_id IS NOT OLD.product_id BEGIN
  SELECT RAISE(ABORT, 'formula container product is immutable');
END;

CREATE TRIGGER bottle_owner_is_immutable
BEFORE UPDATE OF baby_id ON bottle_item
WHEN NEW.baby_id IS NOT OLD.baby_id BEGIN
  SELECT RAISE(ABORT, 'bottle owner is immutable');
END;

CREATE TRIGGER moment_owner_is_immutable
BEFORE UPDATE OF baby_id ON moment
WHEN NEW.baby_id IS NOT OLD.baby_id BEGIN
  SELECT RAISE(ABORT, 'moment owner is immutable');
END;

CREATE TRIGGER media_asset_identity_is_immutable
BEFORE UPDATE OF baby_id, purpose ON media_asset
WHEN NEW.baby_id IS NOT OLD.baby_id OR NEW.purpose IS NOT OLD.purpose BEGIN
  SELECT RAISE(ABORT, 'media asset owner and purpose are immutable');
END;

CREATE TRIGGER moment_group_change_preserves_assets
BEFORE UPDATE OF group_local_date ON moment
WHEN EXISTS (
  SELECT 1 FROM moment_asset ma JOIN media_asset a ON a.id = ma.asset_id
  WHERE ma.moment_id = OLD.id
    AND (a.baby_id IS NOT NEW.baby_id OR a.purpose <> 'moment'
      OR a.captured_baby_local_date IS NOT NEW.group_local_date)
) BEGIN
  SELECT RAISE(ABORT, 'detach moment assets before regrouping');
END;

CREATE TRIGGER media_moment_date_preserves_link
BEFORE UPDATE OF captured_baby_local_date ON media_asset
WHEN EXISTS (
  SELECT 1 FROM moment_asset ma JOIN moment m ON m.id = ma.moment_id
  WHERE ma.asset_id = OLD.id
    AND (m.baby_id IS NOT NEW.baby_id OR NEW.purpose <> 'moment'
      OR m.group_local_date IS NOT NEW.captured_baby_local_date)
) BEGIN
  SELECT RAISE(ABORT, 'detach media from moment before changing captured date');
END;

CREATE TRIGGER immutable_formula_product_version
BEFORE UPDATE ON formula_product_version BEGIN SELECT RAISE(ABORT, 'immutable version'); END;
CREATE TRIGGER immutable_formula_container_version
BEFORE UPDATE ON formula_container_version BEGIN SELECT RAISE(ABORT, 'immutable version'); END;
CREATE TRIGGER immutable_bottle_identity_version
BEFORE UPDATE ON bottle_identity_version BEGIN SELECT RAISE(ABORT, 'immutable version'); END;

CREATE TRIGGER formula_use_validate_insert
BEFORE INSERT ON formula_use BEGIN
  SELECT CASE WHEN (SELECT count(*) FROM formula_use WHERE feeding_event_id = NEW.feeding_event_id) >= 2
    THEN RAISE(ABORT, 'at most two formula containers') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e
    JOIN feeding_detail f ON f.event_id = e.id
    JOIN formula_container_version cv ON cv.id = NEW.container_version_id
    JOIN formula_container c ON c.id = cv.container_id
    JOIN formula_product p ON p.id = c.product_id
    WHERE e.id = NEW.feeding_event_id AND e.type = 'bottle'
      AND f.mode = 'bottle' AND f.milk_type = 'formula' AND p.baby_id = e.baby_id
  ) THEN RAISE(ABORT, 'formula use mismatch') END;
END;

CREATE TRIGGER formula_use_relation_is_immutable
BEFORE UPDATE OF feeding_event_id, container_version_id ON formula_use
WHEN NEW.feeding_event_id IS NOT OLD.feeding_event_id
  OR NEW.container_version_id IS NOT OLD.container_version_id BEGIN
  SELECT RAISE(ABORT, 'delete and recreate formula use relation');
END;

CREATE TRIGGER bottle_use_validate_insert
BEFORE INSERT ON bottle_use BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM care_event e
    JOIN feeding_detail f ON f.event_id = e.id
    JOIN bottle_identity_version bv ON bv.id = NEW.bottle_version_id
    JOIN bottle_item b ON b.id = bv.bottle_id
    WHERE e.id = NEW.feeding_event_id AND e.type = 'bottle'
      AND f.mode = 'bottle' AND b.baby_id = e.baby_id
  ) THEN RAISE(ABORT, 'bottle use mismatch') END;
END;

CREATE TRIGGER bottle_use_is_immutable
BEFORE UPDATE ON bottle_use BEGIN
  SELECT RAISE(ABORT, 'delete and recreate bottle use relation');
END;

CREATE TRIGGER moment_asset_validate_insert
BEFORE INSERT ON moment_asset BEGIN
  SELECT CASE WHEN (SELECT count(*) FROM moment_asset WHERE moment_id = NEW.moment_id) >= 9
    THEN RAISE(ABORT, 'at most nine moment assets') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM moment m JOIN media_asset a ON a.id = NEW.asset_id
    WHERE m.id = NEW.moment_id AND a.purpose = 'moment'
      AND a.baby_id = m.baby_id AND a.captured_baby_local_date = m.group_local_date
  ) THEN RAISE(ABORT, 'moment asset mismatch') END;
END;

CREATE TRIGGER moment_asset_relation_is_immutable
BEFORE UPDATE OF moment_id, asset_id ON moment_asset
WHEN NEW.moment_id IS NOT OLD.moment_id OR NEW.asset_id IS NOT OLD.asset_id BEGIN
  SELECT RAISE(ABORT, 'delete and recreate moment asset relation');
END;

CREATE TRIGGER formula_evidence_validate_insert
BEFORE INSERT ON formula_evidence BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM formula_container_version cv
    JOIN formula_container c ON c.id = cv.container_id
    JOIN formula_product p ON p.id = c.product_id
    JOIN media_asset a ON a.id = NEW.asset_id
    WHERE cv.id = NEW.container_version_id AND a.baby_id = p.baby_id
      AND ((NEW.evidence_type = 'front' AND a.purpose = 'formula_front')
        OR (NEW.evidence_type = 'lot_date' AND a.purpose = 'formula_lot')
        OR (NEW.evidence_type = 'trace' AND a.purpose = 'formula_trace'))
  ) THEN RAISE(ABORT, 'formula evidence mismatch') END;
END;

CREATE TRIGGER formula_evidence_identity_is_immutable
BEFORE UPDATE OF container_version_id, asset_id, evidence_type, capture_source ON formula_evidence
WHEN NEW.container_version_id IS NOT OLD.container_version_id
  OR NEW.asset_id IS NOT OLD.asset_id
  OR NEW.evidence_type IS NOT OLD.evidence_type
  OR NEW.capture_source IS NOT OLD.capture_source BEGIN
  SELECT RAISE(ABORT, 'delete and recreate formula evidence relation');
END;

CREATE TRIGGER bottle_evidence_validate_insert
BEFORE INSERT ON bottle_evidence BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM bottle_identity_version bv
    JOIN bottle_item b ON b.id = bv.bottle_id
    JOIN media_asset a ON a.id = NEW.asset_id
    WHERE bv.id = NEW.bottle_version_id AND a.baby_id = b.baby_id AND a.purpose = 'bottle'
  ) THEN RAISE(ABORT, 'bottle evidence mismatch') END;
END;

CREATE TRIGGER bottle_evidence_identity_is_immutable
BEFORE UPDATE OF bottle_version_id, asset_id, evidence_type, capture_source ON bottle_evidence
WHEN NEW.bottle_version_id IS NOT OLD.bottle_version_id
  OR NEW.asset_id IS NOT OLD.asset_id
  OR NEW.evidence_type IS NOT OLD.evidence_type
  OR NEW.capture_source IS NOT OLD.capture_source BEGIN
  SELECT RAISE(ABORT, 'delete and recreate bottle evidence relation');
END;

CREATE TRIGGER avatar_asset_validate_insert
BEFORE INSERT ON baby_profile
WHEN NEW.avatar_asset_id IS NOT NULL BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM media_asset a WHERE a.id = NEW.avatar_asset_id
      AND a.baby_id = NEW.id AND a.purpose = 'avatar'
  ) THEN RAISE(ABORT, 'avatar asset mismatch') END;
END;

CREATE TRIGGER avatar_asset_validate_update
BEFORE UPDATE OF avatar_asset_id ON baby_profile
WHEN NEW.avatar_asset_id IS NOT NULL BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM media_asset a WHERE a.id = NEW.avatar_asset_id
      AND a.baby_id = NEW.id AND a.purpose = 'avatar'
  ) THEN RAISE(ABORT, 'avatar asset mismatch') END;
END;

CREATE TRIGGER active_module_cannot_be_disabled
BEFORE UPDATE OF is_enabled ON module_preference
WHEN NEW.is_enabled = 0 AND NEW.module_type IN ('nursing','pumping','sleep')
 AND EXISTS (
   SELECT 1 FROM timer_session s
   WHERE s.type = NEW.module_type AND s.deleted_at_ms IS NULL
     AND s.state IN ('ready','running','paused','waiting_for_side','finalizing')
 ) BEGIN
  SELECT RAISE(ABORT, 'active timer module cannot be disabled');
END;
