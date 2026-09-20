-- 000007_user_locations.up.sql
-- Store authoratative, latest user location for proximity validation
-- Minimum required: latitude, longitude, accuracy, timestamp, user ID
-- Does not store unnecessary historical location data

CREATE TABLE IF NOT EXISTS user_locations (
    user_id UUID NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters DOUBLE PRECISION NOT NULL DEFAULT 10.0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_locations PRIMARY KEY (user_id),
    CONSTRAINT fk_user_locations_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_user_locations_lat CHECK (latitude >= -90.0 AND latitude <= 90.0),
    CONSTRAINT chk_user_locations_lon CHECK (longitude >= -180.0 AND longitude <= 180.0)
);

CREATE INDEX IF NOT EXISTS idx_user_locations_updated_at ON user_locations (updated_at);
