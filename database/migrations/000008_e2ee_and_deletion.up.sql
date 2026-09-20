-- 000008_e2ee_and_deletion.up.sql
-- Adds deletion tracking to partitioned messages and media, and creates crypto identities table.

-- 1. Alter messages table to add deletion tracking
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;

-- Create partial index for deleted message queries (offline sync)
CREATE INDEX IF NOT EXISTS idx_messages_deletions ON messages (room_id, deleted_at) WHERE is_deleted = TRUE;

-- 2. Alter media_metadata table to add deletion tracking and room association
CREATE TABLE IF NOT EXISTS media_metadata (
    id UUID NOT NULL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    size BIGINT NOT NULL,
    s3_key VARCHAR(500) NOT NULL,
    owner_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;
ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS room_id UUID NULL;

CREATE INDEX IF NOT EXISTS idx_media_metadata_deleted ON media_metadata (id) WHERE is_deleted = FALSE;

-- 3. Create user_crypto_identities table for public identity and prekey registration
CREATE TABLE IF NOT EXISTS user_crypto_identities (
    user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    identity_key_pub TEXT NOT NULL,
    signed_prekey_pub TEXT NOT NULL,
    signed_prekey_sig TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
