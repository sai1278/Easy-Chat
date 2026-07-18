-- 000004_read_receipts.up.sql
CREATE TABLE IF NOT EXISTS message_receipts (
    message_id UUID NOT NULL,
    room_id UUID NOT NULL,
    user_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL, -- 'DELIVERED', 'READ'
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_message_receipts PRIMARY KEY (room_id, message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_receipts_user ON message_receipts (user_id);
