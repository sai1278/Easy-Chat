-- 000009_auth_and_user_schema_alignment.down.sql
-- Rolls back auth and user schema alignment.
-- NOTE: Once production data exists, dropping these columns results in permanent credential and identity loss.

-- 1. Drop created indexes
DROP INDEX IF EXISTS idx_user_sessions_lookup;
DROP INDEX IF EXISTS idx_users_device_id;

-- 2. Drop added columns from 'user_sessions'
ALTER TABLE user_sessions DROP COLUMN IF EXISTS updated_at;
ALTER TABLE user_sessions DROP COLUMN IF EXISTS is_revoked;
ALTER TABLE user_sessions DROP COLUMN IF EXISTS role;
ALTER TABLE user_sessions DROP COLUMN IF EXISTS device_id;

-- 3. Drop added columns from 'users'
ALTER TABLE users DROP COLUMN IF EXISTS display_name;
ALTER TABLE users DROP COLUMN IF EXISTS password_hash;
ALTER TABLE users DROP COLUMN IF EXISTS role;
ALTER TABLE users DROP COLUMN IF EXISTS device_id;
ALTER TABLE users DROP COLUMN IF EXISTS pseudonym;
