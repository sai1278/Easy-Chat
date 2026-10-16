-- 000010_user_recovery_and_device_registry.up.sql
-- Installs anonymous account recovery keys, physical device binding registry,
-- recovery idempotency cache, and compliance erasure cleanup trigger.

-- =====================================================
-- 1. USER RECOVERY KEYS TABLE
-- =====================================================
-- Stores BIP-39 derived lookup identifiers and Argon2id verifiers.
-- The server never receives or stores plaintext 12-word phrases or master seeds.
CREATE TABLE user_recovery_keys (
    lookup_id         VARCHAR(64)  NOT NULL,
    user_id           UUID         NOT NULL,
    verifier_hash     BYTEA        NOT NULL,
    verifier_salt     BYTEA        NOT NULL,
    failed_attempts   INT          NOT NULL DEFAULT 0,
    locked_until      TIMESTAMPTZ  NULL,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_recovered_at TIMESTAMPTZ  NULL,
    CONSTRAINT pk_user_recovery_keys PRIMARY KEY (lookup_id),
    CONSTRAINT uq_user_recovery_keys_user UNIQUE (user_id),
    CONSTRAINT uq_user_recovery_keys_lookup_user UNIQUE (lookup_id, user_id),
    CONSTRAINT fk_user_recovery_keys_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_lookup_id_hex CHECK (lookup_id ~ '^[0-9a-f]{64}$'),
    CONSTRAINT chk_failed_attempts_nonneg CHECK (failed_attempts >= 0)
);

-- =====================================================
-- 2. USER DEVICE REGISTRY TABLE
-- =====================================================
-- Tracks physical device bindings for single-active-device anonymous recovery.
CREATE TABLE user_device_registry (
    device_id   VARCHAR(255) NOT NULL,
    user_id     UUID         NOT NULL,
    platform    VARCHAR(20)  NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_device_registry PRIMARY KEY (device_id),
    CONSTRAINT fk_user_device_registry_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_device_platform CHECK (platform IN ('IOS', 'ANDROID'))
);

CREATE INDEX IF NOT EXISTS idx_user_device_registry_user ON user_device_registry (user_id);

-- =====================================================
-- 3. RECOVERY IDEMPOTENCY RECORDS TABLE
-- =====================================================
-- Caches encrypted session response bundles for deterministic network replay.
-- References partitioned 'user_sessions' table via composite key (session_created_at, session_id).
CREATE TABLE recovery_idempotency_records (
    idempotency_key     VARCHAR(36)  NOT NULL,
    lookup_id           VARCHAR(64)  NOT NULL,
    user_id             UUID         NOT NULL,
    request_hash        VARCHAR(64)  NOT NULL,
    session_id          UUID         NOT NULL,
    session_created_at  TIMESTAMPTZ  NOT NULL,
    encrypted_bundle    BYTEA        NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at          TIMESTAMPTZ  NOT NULL,
    CONSTRAINT pk_recovery_idempotency_records PRIMARY KEY (idempotency_key),
    CONSTRAINT fk_recovery_idempotency_recovery_key FOREIGN KEY (lookup_id, user_id) REFERENCES user_recovery_keys (lookup_id, user_id) ON DELETE CASCADE,
    CONSTRAINT fk_recovery_idempotency_session FOREIGN KEY (session_created_at, session_id) REFERENCES user_sessions (created_at, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_recovery_idempotency_lookup ON recovery_idempotency_records (lookup_id);
CREATE INDEX IF NOT EXISTS idx_recovery_idempotency_expires ON recovery_idempotency_records (expires_at);

-- =====================================================
-- 4. SUPPORTING INDEX ON USER SESSIONS
-- =====================================================
-- Accelerates device-scoped session queries and revocations across monthly partitions.
CREATE INDEX IF NOT EXISTS idx_user_sessions_device_id ON user_sessions (device_id);

-- =====================================================
-- 5. COMPLIANCE ERASURE CLEANUP TRIGGER
-- =====================================================
-- Synchronously purges recovery credentials and device registry bindings when
-- compliance service pseudonymizes an erased user (compliance.go lines 445-450).
-- Cascades automatically to recovery_idempotency_records.
CREATE OR REPLACE FUNCTION trg_cleanup_erased_user_recovery()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.password_hash IS DISTINCT FROM 'ERASED'
       AND NEW.password_hash = 'ERASED'
       AND LEFT(NEW.device_id, 7) = 'ERASED_'
       AND LEFT(NEW.pseudonym, 13) = 'deleted_user_' THEN

        DELETE FROM user_recovery_keys WHERE user_id = NEW.id;
        DELETE FROM user_device_registry WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_compliance_erasure
AFTER UPDATE OF password_hash, device_id, pseudonym ON users
FOR EACH ROW
EXECUTE FUNCTION trg_cleanup_erased_user_recovery();
