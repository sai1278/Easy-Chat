-- 000001_init_schema.down.sql
-- Tears down tables, indexes, and custom types registered in the init schema.

DROP TABLE IF EXISTS friendships;
DROP TABLE IF EXISTS user_blocks;
DROP TABLE IF EXISTS user_settings;
DROP TABLE IF EXISTS push_tokens;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS profiles;
DROP TABLE IF EXISTS users;

DROP TYPE IF EXISTS device_platform;
DROP TYPE IF EXISTS user_status;

DROP FUNCTION IF EXISTS generate_uuid_v7();
DROP EXTENSION IF EXISTS "uuid-ossp";
