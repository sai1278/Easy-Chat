-- 000008_e2ee_and_deletion.down.sql
DROP TABLE IF EXISTS user_crypto_identities;

DROP INDEX IF EXISTS idx_media_metadata_deleted;
ALTER TABLE media_metadata DROP COLUMN IF EXISTS room_id;
ALTER TABLE media_metadata DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE media_metadata DROP COLUMN IF EXISTS is_deleted;

DROP INDEX IF EXISTS idx_messages_deletions;
ALTER TABLE messages DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE messages DROP COLUMN IF EXISTS is_deleted;
