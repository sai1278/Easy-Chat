-- 000010_user_recovery_and_device_registry.down.sql
-- Rolls back user recovery keys, device registry, idempotency records, and compliance erasure trigger.

-- 1. Drop compliance erasure trigger and function from partitioned parent table 'users'
DROP TRIGGER IF EXISTS trg_users_compliance_erasure ON users;
DROP FUNCTION IF EXISTS trg_cleanup_erased_user_recovery();

-- 2. Drop supporting index on partitioned table 'user_sessions'
DROP INDEX IF EXISTS idx_user_sessions_device_id;

-- 3. Drop recovery idempotency records table (and its indexes)
DROP TABLE IF EXISTS recovery_idempotency_records;

-- 4. Drop user device registry table
DROP TABLE IF EXISTS user_device_registry;

-- 5. Drop user recovery keys table
DROP TABLE IF EXISTS user_recovery_keys;
