-- 000005_performance_optimization_indexes.up.sql
-- Optimizes historical messaging lookup queries by room
CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages (room_id, created_at ASC);
