-- 000002_chat_and_messaging.up.sql
-- Creates messaging rooms, range partitioned message channels, attachments, presence indicators, and session blocks.

-- =====================================================
-- 1. TYPES & ENUMS
-- =====================================================
CREATE TYPE session_state AS ENUM ('ACTIVE', 'REVOKED', 'EXPIRED');

-- =====================================================
-- 2. USER SESSIONS TABLE (RANGE PARTITIONED BY MONTH)
-- =====================================================
CREATE TABLE user_sessions (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    user_id UUID NOT NULL,
    refresh_token_hash VARCHAR(64) NOT NULL,
    state session_state NOT NULL DEFAULT 'ACTIVE',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ NULL,
    CONSTRAINT pk_user_sessions PRIMARY KEY (created_at, id)
) PARTITION BY RANGE (created_at);

CREATE TABLE user_sessions_historical PARTITION OF user_sessions FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m01 PARTITION OF user_sessions FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m02 PARTITION OF user_sessions FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m03 PARTITION OF user_sessions FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m04 PARTITION OF user_sessions FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m05 PARTITION OF user_sessions FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m06 PARTITION OF user_sessions FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m07 PARTITION OF user_sessions FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m08 PARTITION OF user_sessions FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m09 PARTITION OF user_sessions FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m10 PARTITION OF user_sessions FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m11 PARTITION OF user_sessions FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE user_sessions_y2026m12 PARTITION OF user_sessions FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE user_sessions_y2027m01 PARTITION OF user_sessions FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2027-02-01 00:00:00+00');
CREATE TABLE user_sessions_y2027m02 PARTITION OF user_sessions FOR VALUES FROM ('2027-02-01 00:00:00+00') TO ('2027-03-01 00:00:00+00');
CREATE TABLE user_sessions_y2027m03 PARTITION OF user_sessions FOR VALUES FROM ('2027-03-01 00:00:00+00') TO ('2027-04-01 00:00:00+00');

-- Define partial indexing for token check optimizations
CREATE INDEX idx_active_sessions_partial
ON user_sessions (user_id)
WHERE state = 'ACTIVE' AND revoked_at IS NULL;

-- =====================================================
-- 3. CHAT ROOMS TABLE
-- =====================================================
CREATE TABLE chat_rooms (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    initiator_id UUID NOT NULL,
    acceptor_id UUID NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMPTZ NULL,
    CONSTRAINT pk_chat_rooms PRIMARY KEY (id),
    CONSTRAINT fk_chat_rooms_initiator FOREIGN KEY (initiator_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_chat_rooms_acceptor FOREIGN KEY (acceptor_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_different_members CHECK (initiator_id <> acceptor_id)
);

CREATE INDEX idx_chat_rooms_members ON chat_rooms (initiator_id, acceptor_id) WHERE is_active = TRUE;

-- =====================================================
-- 4. MESSAGES TABLE (RANGE PARTITIONED BY MONTH)
-- =====================================================
CREATE TABLE messages (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    room_id UUID NOT NULL,
    sender_id UUID NOT NULL,
    encrypted_payload BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_messages PRIMARY KEY (created_at, id),
    CONSTRAINT fk_messages_rooms FOREIGN KEY (room_id) REFERENCES chat_rooms (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE
) PARTITION BY RANGE (created_at);

CREATE TABLE messages_historical PARTITION OF messages FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');
CREATE TABLE messages_y2026m01 PARTITION OF messages FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE messages_y2026m02 PARTITION OF messages FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE messages_y2026m03 PARTITION OF messages FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE messages_y2026m04 PARTITION OF messages FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE messages_y2026m05 PARTITION OF messages FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE messages_y2026m06 PARTITION OF messages FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE messages_y2026m07 PARTITION OF messages FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE messages_y2026m08 PARTITION OF messages FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE messages_y2026m09 PARTITION OF messages FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE messages_y2026m10 PARTITION OF messages FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE messages_y2026m11 PARTITION OF messages FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE messages_y2026m12 PARTITION OF messages FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE messages_y2027m01 PARTITION OF messages FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2027-02-01 00:00:00+00');
CREATE TABLE messages_y2027m02 PARTITION OF messages FOR VALUES FROM ('2027-02-01 00:00:00+00') TO ('2027-03-01 00:00:00+00');
CREATE TABLE messages_y2027m03 PARTITION OF messages FOR VALUES FROM ('2027-03-01 00:00:00+00') TO ('2027-04-01 00:00:00+00');

CREATE INDEX idx_messages_room_lookup ON messages (room_id);

-- =====================================================
-- 5. ATTACHMENTS TABLE (RANGE PARTITIONED BY MONTH)
-- =====================================================
CREATE TABLE attachments (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    message_id UUID NOT NULL,
    message_created_at TIMESTAMPTZ NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size INTEGER NOT NULL,
    encrypted_data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_attachments PRIMARY KEY (created_at, id),
    CONSTRAINT chk_file_size CHECK (file_size > 0)
) PARTITION BY RANGE (created_at);

CREATE TABLE attachments_historical PARTITION OF attachments FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');
CREATE TABLE attachments_y2026m01 PARTITION OF attachments FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE attachments_y2026m02 PARTITION OF attachments FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE attachments_y2026m03 PARTITION OF attachments FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE attachments_y2026m04 PARTITION OF attachments FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE attachments_y2026m05 PARTITION OF attachments FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE attachments_y2026m06 PARTITION OF attachments FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE attachments_y2026m07 PARTITION OF attachments FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE attachments_y2026m08 PARTITION OF attachments FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE attachments_y2026m09 PARTITION OF attachments FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE attachments_y2026m10 PARTITION OF attachments FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE attachments_y2026m11 PARTITION OF attachments FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE attachments_y2026m12 PARTITION OF attachments FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE attachments_y2027m01 PARTITION OF attachments FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2027-02-01 00:00:00+00');
CREATE TABLE attachments_y2027m02 PARTITION OF attachments FOR VALUES FROM ('2027-02-01 00:00:00+00') TO ('2027-03-01 00:00:00+00');
CREATE TABLE attachments_y2027m03 PARTITION OF attachments FOR VALUES FROM ('2027-03-01 00:00:00+00') TO ('2027-04-01 00:00:00+00');

CREATE INDEX idx_attachments_msg ON attachments (message_id);

-- =====================================================
-- 6. PRESENCE TABLE (STATIC PRESENCE MAPPINGS)
-- =====================================================
CREATE TABLE presence (
    user_id UUID NOT NULL,
    is_visible BOOLEAN NOT NULL DEFAULT FALSE,
    h3_index VARCHAR(15) NULL, -- Snaps to Uber H3 hex grid (e.g. "8a2a1072b59ffff")
    radius_meters INTEGER NOT NULL DEFAULT 100,
    last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_presence PRIMARY KEY (user_id),
    CONSTRAINT fk_presence_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_presence_radius CHECK (radius_meters BETWEEN 100 AND 200)
);

-- Index visibility to support active geographic search queries
CREATE INDEX idx_presence_search ON presence (h3_index) WHERE is_visible = TRUE;

-- =====================================================
-- 7. RATE LIMITS TABLE
-- =====================================================
CREATE TABLE rate_limits (
    rate_key VARCHAR(64) NOT NULL, -- SHA-256 hash of IP/Auth identity
    endpoint VARCHAR(100) NOT NULL,
    request_tokens INT NOT NULL DEFAULT 1,
    last_request TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rate_limits PRIMARY KEY (rate_key, endpoint),
    CONSTRAINT chk_tokens CHECK (request_tokens >= 0)
);
