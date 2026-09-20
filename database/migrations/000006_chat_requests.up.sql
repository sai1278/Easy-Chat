-- 000006_chat_requests.up.sql
-- Chat request workflow: PENDING, ACCEPTED, DENIED, CANCELLED

CREATE TABLE IF NOT EXISTS chat_requests (
    id UUID NOT NULL DEFAULT generate_uuid_v7(),
    sender_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    room_id UUID NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMPTZ NULL,
    CONSTRAINT pk_chat_requests PRIMARY KEY (id),
    CONSTRAINT fk_chat_requests_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_chat_requests_recipient FOREIGN KEY (recipient_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_chat_requests_room FOREIGN KEY (room_id) REFERENCES chat_rooms (id) ON DELETE SET NULL,
    CONSTRAINT chk_chat_requests_different_users CHECK (sender_id <> recipient_id),
    CONSTRAINT chk_chat_requests_status CHECK (status IN ('PENDING', 'ACCEPTED', 'DENIED', 'CANCELLED'))
);

CREATE INDEX IF NOT EXISTS idx_chat_requests_recipient ON chat_requests (recipient_id, status);
CREATE INDEX IF NOT EXISTS idx_chat_requests_sender ON chat_requests (sender_id, status);
CREATE INDEX IF NOT EXISTS idx_chat_requests_pair ON chat_requests (sender_id, recipient_id);
