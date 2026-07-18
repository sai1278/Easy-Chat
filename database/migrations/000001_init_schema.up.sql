-- 000001_init_schema.up.sql
-- Bootstraps core extensions, custom UUIDv7 generator, custom types, and partitioned user tables.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- 1. CUSTOM PL/pgSQL UUIDv7 GENERATOR
-- =====================================================
-- Generates time-ordered, lexicographically sortable UUIDs (RFC 9562).
-- Layout: tttttttt-tttt-7aaa-ybbb-bbbbbbbbbbbb
CREATE OR REPLACE FUNCTION generate_uuid_v7() RETURNS uuid AS $$
DECLARE
  v_time double precision;
  v_send_ms bigint;
  v_unix_ts_ms_hex varchar;
  v_rand_a_hex varchar;
  v_rand_b_hex varchar;
BEGIN
  -- Get current time in decimal seconds
  v_time := EXTRACT(EPOCH FROM clock_timestamp());
  v_send_ms := floor(v_time * 1000)::bigint;
  
  -- Hex representation of timestamp (padded to 12 chars / 48 bits)
  v_unix_ts_ms_hex := lpad(to_hex(v_send_ms), 12, '0');
  
  -- Generate random hex parts
  v_rand_a_hex := lpad(to_hex((random() * 4095)::integer), 3, '0');
  v_rand_b_hex := lpad(to_hex((random() * 1152921504606846975)::bigint), 15, '0');
  
  -- Format hex output string into UUID standard
  RETURN (
    substr(v_unix_ts_ms_hex, 1, 8) || '-' ||
    substr(v_unix_ts_ms_hex, 9, 4) || '-' ||
    '7' || v_rand_a_hex || '-' ||
    (case floor(random()*4)::int
      when 0 then '8'
      when 1 then '9'
      when 2 then 'a'
      else 'b'
     end) || substr(v_rand_b_hex, 1, 3) || '-' ||
    substr(v_rand_b_hex, 4, 12)
  )::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- =====================================================
-- 2. CUSTOM TYPES & ENUMS
-- =====================================================
CREATE TYPE user_status AS ENUM ('ACTIVE', 'SUSPENDED', 'DELETED');
CREATE TYPE device_platform AS ENUM ('IOS', 'ANDROID');

-- =====================================================
-- 3. USERS TABLE (HASH PARTITIONED - 16 DIVISOR)
-- =====================================================
CREATE TABLE users (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    status user_status NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_users PRIMARY KEY (id)
) PARTITION BY HASH (id);

-- Bind 16 child partitions
CREATE TABLE users_p0  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE users_p1  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE users_p2  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE users_p3  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE users_p4  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE users_p5  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE users_p6  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE users_p7  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE users_p8  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE users_p9  PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE users_p10 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE users_p11 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE users_p12 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE users_p13 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE users_p14 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE users_p15 PARTITION OF users FOR VALUES WITH (MODULUS 16, REMAINDER 15);

-- =====================================================
-- 4. PROFILES TABLE (HASH PARTITIONED BY USER_ID)
-- =====================================================
CREATE TABLE profiles (
    user_id UUID NOT NULL,
    pseudonym VARCHAR(50) NOT NULL,
    avatar_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_profiles PRIMARY KEY (user_id),
    CONSTRAINT fk_profiles_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_pseudonym_format CHECK (pseudonym ~* '^[a-z]+ [a-z]+$'),
    CONSTRAINT chk_avatar_id CHECK (avatar_id > 0)
) PARTITION BY HASH (user_id);

CREATE TABLE profiles_p0  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE profiles_p1  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE profiles_p2  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE profiles_p3  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE profiles_p4  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE profiles_p5  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE profiles_p6  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE profiles_p7  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE profiles_p8  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE profiles_p9  PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE profiles_p10 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE profiles_p11 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE profiles_p12 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE profiles_p13 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE profiles_p14 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE profiles_p15 PARTITION OF profiles FOR VALUES WITH (MODULUS 16, REMAINDER 15);

-- =====================================================
-- 5. DEVICES TABLE (HASH PARTITIONED BY USER_ID)
-- =====================================================
CREATE TABLE devices (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    user_id UUID NOT NULL,
    device_uid VARCHAR(255) NOT NULL, -- unique hash of device HW profile
    platform device_platform NOT NULL,
    os_version VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_devices PRIMARY KEY (user_id, id),
    CONSTRAINT fk_devices_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) PARTITION BY HASH (user_id);

CREATE TABLE devices_p0  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE devices_p1  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE devices_p2  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE devices_p3  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE devices_p4  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE devices_p5  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE devices_p6  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE devices_p7  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE devices_p8  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE devices_p9  PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE devices_p10 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE devices_p11 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE devices_p12 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE devices_p13 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE devices_p14 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE devices_p15 PARTITION OF devices FOR VALUES WITH (MODULUS 16, REMAINDER 15);

-- =====================================================
-- 6. PUSH TOKENS TABLE (HASH PARTITIONED BY USER_ID)
-- =====================================================
CREATE TABLE push_tokens (
    user_id UUID NOT NULL,
    push_token VARCHAR(255) NOT NULL,
    is_valid BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_push_tokens PRIMARY KEY (user_id, push_token),
    CONSTRAINT fk_push_tokens_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) PARTITION BY HASH (user_id);

CREATE TABLE push_tokens_p0  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE push_tokens_p1  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE push_tokens_p2  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE push_tokens_p3  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE push_tokens_p4  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE push_tokens_p5  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE push_tokens_p6  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE push_tokens_p7  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE push_tokens_p8  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE push_tokens_p9  PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE push_tokens_p10 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE push_tokens_p11 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE push_tokens_p12 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE push_tokens_p13 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE push_tokens_p14 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE push_tokens_p15 PARTITION OF push_tokens FOR VALUES WITH (MODULUS 16, REMAINDER 15);

-- =====================================================
-- 7. USER SETTINGS TABLE (HASH PARTITIONED BY USER_ID)
-- =====================================================
CREATE TABLE user_settings (
    user_id UUID NOT NULL,
    default_radius_meters INTEGER NOT NULL DEFAULT 100,
    visible_mode_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    auto_purge_local_history BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_settings PRIMARY KEY (user_id),
    CONSTRAINT fk_settings_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_radius CHECK (default_radius_meters BETWEEN 100 AND 200)
) PARTITION BY HASH (user_id);

CREATE TABLE user_settings_p0  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE user_settings_p1  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE user_settings_p2  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE user_settings_p3  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE user_settings_p4  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE user_settings_p5  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE user_settings_p6  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE user_settings_p7  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE user_settings_p8  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE user_settings_p9  PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE user_settings_p10 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE user_settings_p11 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE user_settings_p12 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE user_settings_p13 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE user_settings_p14 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE user_settings_p15 PARTITION OF user_settings FOR VALUES WITH (MODULUS 16, REMAINDER 15);

-- =====================================================
-- 8. USER BLOCKS TABLE (NORMAL TABLE WITH COMPOSITE INDEX)
-- =====================================================
CREATE TABLE user_blocks (
    blocker_id UUID NOT NULL,
    blocked_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_blocks PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT fk_blocks_blocker FOREIGN KEY (blocker_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_blocks_blocked FOREIGN KEY (blocked_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_no_self_block CHECK (blocker_id <> blocked_id)
);

CREATE INDEX idx_user_blocks_reversed ON user_blocks (blocked_id, blocker_id);

-- =====================================================
-- 9. FRIENDSHIPS TABLE
-- =====================================================
CREATE TABLE friendships (
    user_a_id UUID NOT NULL,
    user_b_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_friendships PRIMARY KEY (user_a_id, user_b_id),
    CONSTRAINT fk_friendships_a FOREIGN KEY (user_a_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_friendships_b FOREIGN KEY (user_b_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_no_self_friend CHECK (user_a_id <> user_b_id)
);

CREATE INDEX idx_friendships_reversed ON friendships (user_b_id, user_a_id);
