-- 000003_jobs_and_auditing.down.sql
-- Tears down background jobs, moderation events, audit logs, and maintenance functions.

DROP FUNCTION IF EXISTS purge_inactive_profiles(INT);

DROP TABLE IF EXISTS analytics_metadata;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS moderation_events;
DROP TABLE IF EXISTS background_jobs;

DROP TYPE IF EXISTS job_state;
