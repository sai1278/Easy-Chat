-- ══════════════════════════════════════════════════════════════════════════════
-- GDPR Compliance Database Schema
-- Platform: Nearby Connect (EasyChat)
-- GDPR References: Art.6 (lawful basis), Art.7 (consent), Art.17 (erasure),
--                  Art.20 (portability), Art.30 (records of processing)
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. CONSENT MANAGEMENT (GDPR Art.7 — Conditions for consent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_consents (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL,
    -- Granular consent purposes (Art.5 — purpose limitation)
    purpose             TEXT        NOT NULL CHECK (purpose IN (
                                        'analytics',
                                        'marketing_emails',
                                        'location_sharing',
                                        'third_party_data',
                                        'essential_service',  -- cannot be withdrawn
                                        'push_notifications'
                                    )),
    granted             BOOLEAN     NOT NULL,
    -- Consent mechanism used (must be freely given, specific, informed, unambiguous)
    mechanism           TEXT        NOT NULL CHECK (mechanism IN (
                                        'explicit_checkbox',
                                        'in_app_prompt',
                                        'account_creation',
                                        'settings_update'
                                    )),
    -- Immutable consent proof
    ip_address_hash     TEXT,       -- SHA-256 of IP at consent time (not raw IP)
    user_agent          TEXT,       -- Browser/app version at consent time
    consent_text_hash   TEXT,       -- SHA-256 of exact consent text shown to user
    consent_text_version VARCHAR(20),
    -- Lifecycle
    granted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    withdrawn_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,      -- For time-limited consents
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_consents_user_id ON user_consents(user_id);
CREATE INDEX idx_user_consents_purpose ON user_consents(purpose);
CREATE INDEX idx_user_consents_granted ON user_consents(user_id, purpose) WHERE granted = true AND withdrawn_at IS NULL;

-- Consent history — append-only audit trail for consent changes
CREATE TABLE IF NOT EXISTS consent_audit_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consent_id      UUID        NOT NULL REFERENCES user_consents(id),
    user_id         UUID        NOT NULL,
    purpose         TEXT        NOT NULL,
    action          TEXT        NOT NULL CHECK (action IN ('granted', 'withdrawn', 'expired', 'updated')),
    actor_id        UUID,               -- system or user who triggered change
    actor_type      TEXT        NOT NULL CHECK (actor_type IN ('user', 'system', 'admin')),
    previous_value  JSONB,
    new_value       JSONB,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Consent audit log is IMMUTABLE (no UPDATE/DELETE allowed)
CREATE INDEX idx_consent_audit_user_id ON consent_audit_log(user_id);
CREATE INDEX idx_consent_audit_created ON consent_audit_log(created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. AUDIT TRAIL (GDPR Art.30 — Records of processing activities)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Who
    actor_id        UUID,               -- NULL for anonymous/system operations
    actor_type      TEXT        NOT NULL CHECK (actor_type IN ('user', 'admin', 'system', 'service')),
    service_name    TEXT        NOT NULL,
    -- What
    event_type      TEXT        NOT NULL,   -- e.g. 'user.login', 'data.export', 'consent.withdrawn'
    resource_type   TEXT        NOT NULL,   -- e.g. 'user', 'message', 'session'
    resource_id     TEXT,
    action          TEXT        NOT NULL,   -- 'created', 'read', 'updated', 'deleted', 'exported'
    -- Result
    outcome         TEXT        NOT NULL CHECK (outcome IN ('success', 'failure', 'partial')),
    failure_reason  TEXT,
    -- Context
    ip_address_hash TEXT,               -- Hashed for privacy
    user_agent      TEXT,
    request_id      TEXT,               -- Correlation ID for request tracing
    region          TEXT,               -- Data residency region
    -- Payload (PII-free — references only, not raw data)
    metadata        JSONB,
    -- Integrity
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Tamper detection: hash of (id + actor_id + event_type + resource_id + created_at)
    integrity_hash  TEXT        NOT NULL
);

-- Audit log is APPEND-ONLY — enforced by Row-Level Security
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_insert_only ON audit_events FOR INSERT TO app_user WITH CHECK (true);
CREATE POLICY audit_no_update ON audit_events FOR UPDATE TO app_user USING (false);
CREATE POLICY audit_no_delete ON audit_events FOR DELETE TO app_user USING (false);

CREATE INDEX idx_audit_events_actor_id ON audit_events(actor_id);
CREATE INDEX idx_audit_events_event_type ON audit_events(event_type);
CREATE INDEX idx_audit_events_resource ON audit_events(resource_type, resource_id);
CREATE INDEX idx_audit_events_created ON audit_events(created_at);
CREATE INDEX idx_audit_events_region ON audit_events(region);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. DATA SUBJECT REQUESTS (GDPR Art.12-22 — Data subject rights)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS data_subject_requests (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL,
    request_type    TEXT        NOT NULL CHECK (request_type IN (
                                    'access',           -- Art.15: Right of access
                                    'portability',      -- Art.20: Data portability
                                    'erasure',          -- Art.17: Right to erasure
                                    'rectification',    -- Art.16: Right to rectification
                                    'restriction',      -- Art.18: Right to restrict processing
                                    'objection'         -- Art.21: Right to object
                                )),
    status          TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN (
                                    'pending',
                                    'in_progress',
                                    'completed',
                                    'rejected',         -- With documented legal basis
                                    'partial'           -- Partially fulfilled
                                )),
    -- GDPR requires response within 30 days (Art.12)
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deadline_at     TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days',
    completed_at    TIMESTAMPTZ,
    -- For portability: download link (signed URL, expires in 7 days)
    export_url      TEXT,
    export_expires  TIMESTAMPTZ,
    -- For erasure: what was deleted
    deletion_summary JSONB,
    -- Rejection reason (must be documented for GDPR compliance)
    rejection_reason TEXT,
    -- Verification
    identity_verified BOOLEAN   NOT NULL DEFAULT false,
    verification_method TEXT,   -- 'email_otp', 'document', 'in_app_auth'
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_dsr_user_id ON data_subject_requests(user_id);
CREATE INDEX idx_dsr_status ON data_subject_requests(status) WHERE status IN ('pending', 'in_progress');
CREATE INDEX idx_dsr_deadline ON data_subject_requests(deadline_at) WHERE status = 'pending';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DATA RETENTION POLICIES (GDPR Art.5(1)(e) — Storage limitation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS data_retention_policies (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name          TEXT        NOT NULL UNIQUE,
    retention_days      INTEGER     NOT NULL,
    -- Legal basis for the retention period
    legal_basis         TEXT        NOT NULL CHECK (legal_basis IN (
                                        'legitimate_interest',
                                        'legal_obligation',     -- e.g. financial records: 7 years
                                        'contractual',
                                        'consent',
                                        'vital_interest'
                                    )),
    -- What happens at retention boundary
    action              TEXT        NOT NULL CHECK (action IN (
                                        'delete',           -- Hard delete
                                        'anonymize',        -- Replace PII with pseudonymous IDs
                                        'archive',          -- Move to cold storage
                                        'pseudonymize'      -- Replace identifiers with tokens
                                    )),
    -- Deletion column (timestamp column to compare against retention_days)
    date_column         TEXT        NOT NULL DEFAULT 'created_at',
    filter_clause       TEXT,               -- Additional SQL WHERE clause
    last_run_at         TIMESTAMPTZ,
    last_run_rows       BIGINT,
    enabled             BOOLEAN     NOT NULL DEFAULT true,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed production retention policies
INSERT INTO data_retention_policies (table_name, retention_days, legal_basis, action, date_column, notes) VALUES
('messages',             365,    'contractual',      'delete',       'created_at',   'Chat messages: 1 year retention'),
('user_sessions',        90,     'legitimate_interest', 'delete',   'created_at',   'Auth sessions: 90-day retention'),
('audit_events',         2555,   'legal_obligation', 'archive',      'created_at',   'Audit logs: 7-year legal obligation (GDPR Art.30)'),
('consent_audit_log',    2555,   'legal_obligation', 'archive',      'created_at',   'Consent history: 7-year retention'),
('data_subject_requests',2555,   'legal_obligation', 'archive',      'created_at',   'DSR records: 7-year legal obligation'),
('user_location_events', 30,     'consent',          'delete',       'recorded_at',  'Location data: 30 days per consent'),
('push_notification_logs',90,    'legitimate_interest','delete',     'sent_at',      'Push logs: 90 days'),
('media_files',          365,    'contractual',      'delete',       'uploaded_at',  'User media: 1 year after upload')
ON CONFLICT (table_name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. DATA RESIDENCY REGISTRY (GDPR Art.44-49 — Data transfers)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_data_residency (
    user_id             UUID        PRIMARY KEY,
    -- Assigned region at account creation (follows user's IP geolocation)
    assigned_region     TEXT        NOT NULL CHECK (assigned_region IN ('eu-west1', 'us-east1', 'us-west1', 'ap-southeast1')),
    -- Data sovereignty classification
    data_sovereignty    TEXT        NOT NULL CHECK (data_sovereignty IN ('gdpr', 'ccpa', 'pdpa', 'standard')),
    -- Cross-border transfer restrictions
    transfer_restricted BOOLEAN     NOT NULL DEFAULT false,
    -- SCCs / BCRs reference if transferred cross-border
    transfer_basis      TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_data_residency_region ON user_data_residency(assigned_region);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. PII PSEUDONYMISATION MAP (GDPR Art.4(5) — Pseudonymisation)
-- Only accessible by compliance service with restricted DB credentials
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pii_pseudonym_map (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    real_user_id    UUID        NOT NULL UNIQUE,
    -- Pseudonym used in analytics/logs (one-way derived, not reversible without this table)
    pseudonym_token TEXT        NOT NULL UNIQUE,
    -- Encryption key reference (actual key in Vault/KMS — not stored here)
    key_version     TEXT        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Pseudonym is invalidated on erasure request
    invalidated_at  TIMESTAMPTZ
);

-- Only the compliance-service DB role can access this table
REVOKE ALL ON pii_pseudonym_map FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON pii_pseudonym_map TO compliance_service;
