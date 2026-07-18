-- 000003_jobs_and_auditing.up.sql
-- Installs background job queues, moderation trackers, BRIN-indexed audit logs, and the profile retention purge function.

-- =====================================================
-- 1. TYPES & ENUMS
-- =====================================================
CREATE TYPE job_state AS ENUM ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED');

-- =====================================================
-- 2. BACKGROUND JOBS TABLE
-- =====================================================
CREATE TABLE background_jobs (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    job_name VARCHAR(100) NOT NULL,
    state job_state NOT NULL DEFAULT 'PENDING',
    parameters JSONB NULL,
    result JSONB NULL,
    error_message TEXT NULL,
    run_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_background_jobs PRIMARY KEY (id)
);

CREATE INDEX idx_background_jobs_queue ON background_jobs (state, run_at) WHERE state IN ('PENDING', 'RUNNING');

-- =====================================================
-- 3. MODERATION EVENTS TABLE
-- =====================================================
CREATE TABLE moderation_events (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    reporter_id UUID NULL, -- NULL indicates system-generated flag
    offender_id UUID NOT NULL,
    reason TEXT NOT NULL,
    action_taken VARCHAR(50) NOT NULL, -- e.g., 'WARNING', 'SUSPENSION', 'BAN'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_moderation_events PRIMARY KEY (id),
    CONSTRAINT fk_moderation_offender FOREIGN KEY (offender_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_moderation_offender ON moderation_events (offender_id);

-- =====================================================
-- 4. AUDIT LOGS TABLE (RANGE PARTITIONED, BRIN INDEXED)
-- =====================================================
CREATE TABLE audit_logs (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    event_type VARCHAR(50) NOT NULL,
    details JSONB NULL, -- Structured metrics (NO plaintext PII)
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_audit_logs PRIMARY KEY (created_at, id)
) PARTITION BY RANGE (created_at);

CREATE TABLE audit_logs_historical PARTITION OF audit_logs FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m01 PARTITION OF audit_logs FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m02 PARTITION OF audit_logs FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m03 PARTITION OF audit_logs FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m04 PARTITION OF audit_logs FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m05 PARTITION OF audit_logs FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m06 PARTITION OF audit_logs FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m07 PARTITION OF audit_logs FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m08 PARTITION OF audit_logs FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m09 PARTITION OF audit_logs FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m10 PARTITION OF audit_logs FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m11 PARTITION OF audit_logs FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE audit_logs_y2026m12 PARTITION OF audit_logs FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE audit_logs_y2027m01 PARTITION OF audit_logs FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2027-02-01 00:00:00+00');
CREATE TABLE audit_logs_y2027m02 PARTITION OF audit_logs FOR VALUES FROM ('2027-02-01 00:00:00+00') TO ('2027-03-01 00:00:00+00');
CREATE TABLE audit_logs_y2027m03 PARTITION OF audit_logs FOR VALUES FROM ('2027-03-01 00:00:00+00') TO ('2027-04-01 00:00:00+00');

-- BRIN (Block Range Index) is extremely fast and lightweight for ordered logs
CREATE INDEX idx_audit_logs_brin_time ON audit_logs USING BRIN (created_at);

-- =====================================================
-- 5. ANALYTICS METADATA TABLE (RANGE PARTITIONED, BRIN INDEXED)
-- =====================================================
CREATE TABLE analytics_metadata (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    metric_name VARCHAR(100) NOT NULL,
    metric_value NUMERIC NOT NULL,
    dimensions JSONB NULL, -- e.g. {"region": "US_WEST_1", "platform": "ANDROID"}
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_analytics_metadata PRIMARY KEY (created_at, id)
) PARTITION BY RANGE (created_at);

CREATE TABLE analytics_metadata_historical PARTITION OF analytics_metadata FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m01 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m02 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m03 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m04 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m05 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m06 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m07 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m08 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m09 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m10 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m11 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2026m12 PARTITION OF analytics_metadata FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2027m01 PARTITION OF analytics_metadata FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2027-02-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2027m02 PARTITION OF analytics_metadata FOR VALUES FROM ('2027-02-01 00:00:00+00') TO ('2027-03-01 00:00:00+00');
CREATE TABLE analytics_metadata_y2027m03 PARTITION OF analytics_metadata FOR VALUES FROM ('2027-03-01 00:00:00+00') TO ('2027-04-01 00:00:00+00');

CREATE INDEX idx_analytics_metadata_brin ON analytics_metadata USING BRIN (created_at);

-- =====================================================
-- 6. AUTOMATED RETENTION PURGE FUNCTION (180 DAYS)
-- =====================================================
-- Batch purges users inactive for more than p_retention_days.
-- Cascade deletes all referencing profiles, sessions, settings, blocks, and messages.
CREATE OR REPLACE FUNCTION purge_inactive_profiles(p_retention_days INT)
RETURNS INT AS $$
DECLARE
  v_deleted_count INT;
BEGIN
  -- Validate configuration boundary sanity check
  IF p_retention_days <= 0 THEN
    RAISE EXCEPTION 'Purge retention days threshold must be greater than zero.';
  END IF;

  WITH deleted_rows AS (
    DELETE FROM users
    WHERE updated_at < (clock_timestamp() - (p_retention_days || ' days')::interval)
    RETURNING id
  )
  SELECT count(*) INTO v_deleted_count FROM deleted_rows;
  
  -- Log the maintenance result into immutable audit logs
  IF v_deleted_count > 0 THEN
    INSERT INTO audit_logs (event_type, details)
    VALUES (
      'SYSTEM_RETENTION_PURGE',
      jsonb_build_object(
        'deleted_count', v_deleted_count,
        'retention_days_threshold', p_retention_days
      )
    );
  END IF;

  RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
