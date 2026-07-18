-- 000002_chat_and_messaging.down.sql
-- Tears down chat, messages, presence, sessions, and rate-limits components.

DROP TABLE IF EXISTS rate_limits;
DROP TABLE IF EXISTS presence;
DROP TABLE IF EXISTS attachments;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS chat_rooms;
DROP TABLE IF EXISTS user_sessions;

DROP TYPE IF EXISTS session_state;
