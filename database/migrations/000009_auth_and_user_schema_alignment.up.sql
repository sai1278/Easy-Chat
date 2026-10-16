-- 000009_auth_and_user_schema_alignment.up.sql
-- Aligns users and user_sessions partitioned tables with microservices domain models.

-- 1. Add missing auth and identity columns to partitioned table 'users'
-- Note: In PostgreSQL, altering a partitioned parent table automatically propagates to all child partitions.
ALTER TABLE users ADD COLUMN IF NOT EXISTS pseudonym VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'anonymous_user';
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT NOT NULL DEFAULT '';

-- 2. Create B-tree index on device_id for fast device-based authentication lookups
-- Note: Normal index (non-unique) because 'users' is hash-partitioned by id. Uniqueness is enforced by application logic.
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users (device_id);

-- 3. Add missing session tracking columns to partitioned table 'user_sessions'
-- Note: Coexists with the existing 'state' enum and 'revoked_at' columns for full backward compatibility.
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'anonymous_user';
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS is_revoked BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- 4. Create index on user_sessions for user session queries
CREATE INDEX IF NOT EXISTS idx_user_sessions_lookup ON user_sessions (user_id, is_revoked);
