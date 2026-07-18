package persistence

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"fmt"
	"time"

	"github.com/lib/pq"
	"nearby/backend/services/chat/internal/domain"
)

// PostgresChatRepository implements domain.ChatRepository.
type PostgresChatRepository struct {
	db *sql.DB
}

// NewPostgresChatRepository creates a new PostgresChatRepository.
// CRIT-10: DDL is no longer run at application startup. Schema management
// is the responsibility of the migrations tool (golang-migrate). If DDL
// is needed for local bootstrap, run it from a migration file, not here.
func NewPostgresChatRepository(db *sql.DB) *PostgresChatRepository {
	return &PostgresChatRepository{db: db}
}

// SaveMessage persists a message payload to PostgreSQL.
func (r *PostgresChatRepository) SaveMessage(ctx context.Context, msg *domain.Message) error {
	query := `
		INSERT INTO messages (id, room_id, sender_id, encrypted_payload, created_at)
		VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.ExecContext(ctx, query, msg.ID, msg.RoomID, msg.SenderID, msg.EncryptedPayload, msg.CreatedAt)
	return err
}

// SaveReceipt inserts or updates a message delivery or read acknowledgement in PostgreSQL.
func (r *PostgresChatRepository) SaveReceipt(ctx context.Context, receipt *domain.ReadReceipt) error {
	query := `
		INSERT INTO message_receipts (message_id, room_id, user_id, status, timestamp)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (room_id, message_id, user_id) 
		DO UPDATE SET status = EXCLUDED.status, timestamp = EXCLUDED.timestamp`
	_, err := r.db.ExecContext(ctx, query, receipt.MessageID, receipt.RoomID, receipt.UserID, receipt.Status, receipt.Timestamp)
	return err
}

// GetRoomMessagesSince retrieves room messages since a specific timestamp for reconnect recovery.
func (r *PostgresChatRepository) GetRoomMessagesSince(ctx context.Context, roomID string, since time.Time) ([]*domain.Message, error) {
	query := `
		SELECT id::text, room_id::text, sender_id::text, encrypted_payload, created_at
		FROM messages
		WHERE room_id = $1 AND created_at > $2
		ORDER BY created_at ASC`
	rows, err := r.db.QueryContext(ctx, query, roomID, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*domain.Message
	for rows.Next() {
		var msg domain.Message
		if err := rows.Scan(&msg.ID, &msg.RoomID, &msg.SenderID, &msg.EncryptedPayload, &msg.CreatedAt); err != nil {
			return nil, err
		}
		messages = append(messages, &msg)
	}
	// CRIT-15: check for errors that occurred during row iteration.
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetRoomMessagesSince rows: %w", err)
	}
	return messages, nil
}

// GetRoomsMessagesSince retrieves messages since a specific timestamp across multiple rooms in a single query with pagination.
func (r *PostgresChatRepository) GetRoomsMessagesSince(ctx context.Context, roomIDs []string, since time.Time, limit, offset int) ([]*domain.Message, error) {
	if len(roomIDs) == 0 {
		return []*domain.Message{}, nil
	}

	query := `
		SELECT id::text, room_id::text, sender_id::text, encrypted_payload, created_at
		FROM messages
		WHERE room_id = ANY($1) AND created_at > $2
		ORDER BY created_at ASC
		LIMIT $3 OFFSET $4`
	rows, err := r.db.QueryContext(ctx, query, pq.Array(roomIDs), since, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*domain.Message
	for rows.Next() {
		var msg domain.Message
		if err := rows.Scan(&msg.ID, &msg.RoomID, &msg.SenderID, &msg.EncryptedPayload, &msg.CreatedAt); err != nil {
			return nil, err
		}
		messages = append(messages, &msg)
	}
	// CRIT-15: check for errors that occurred during row iteration.
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetRoomsMessagesSince rows: %w", err)
	}
	return messages, nil
}

// GetActiveRoomsForUser fetches all active chat rooms for a given user.
func (r *PostgresChatRepository) GetActiveRoomsForUser(ctx context.Context, userID string) ([]string, error) {
	query := `
		SELECT id::text FROM chat_rooms
		WHERE (initiator_id = $1 OR acceptor_id = $1) AND is_active = TRUE`
	rows, err := r.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rooms []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		rooms = append(rooms, id)
	}
	// CRIT-15: check for errors that occurred during row iteration.
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetActiveRoomsForUser rows: %w", err)
	}
	return rooms, nil
}

// PostgresRoomRepository implements domain.RoomRepository.
// It resolves chat room memberships from PostgreSQL for event routing (HIGH-06).
type PostgresRoomRepository struct {
	db *sql.DB
}

// NewPostgresRoomRepository creates a new PostgresRoomRepository.
func NewPostgresRoomRepository(db *sql.DB) *PostgresRoomRepository {
	return &PostgresRoomRepository{db: db}
}

// GetMembers returns the user IDs of all participants in the given room.
func (r *PostgresRoomRepository) GetMembers(ctx context.Context, roomID string) ([]string, error) {
	query := `
		SELECT initiator_id::text, acceptor_id::text
		FROM chat_rooms WHERE id = $1`
	var memberA, memberB string
	err := r.db.QueryRowContext(ctx, query, roomID).Scan(&memberA, &memberB)
	if err != nil {
		return nil, fmt.Errorf("GetMembers: %w", err)
	}
	return []string{memberA, memberB}, nil
}

// GetOrCreateRoom fetches or creates a mutually unique active chat room for the two users.
func (r *PostgresRoomRepository) GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error) {
	// Sort user IDs lexicographically to prevent deadlocks and ensure consistent locking order
	u1, u2 := userA, userB
	if u1 > u2 {
		u1, u2 = u2, u1
	}

	// Start a standard read-committed transaction
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback() // Rollback is safe: no-op if committed

	// Compute a stable, deterministic advisory lock ID for this pair of users
	hash := sha256.Sum256([]byte(u1 + ":" + u2))
	lockKey := int64(binary.BigEndian.Uint64(hash[:8]))

	// Obtain transactional advisory lock. This lock is automatically released when the transaction ends.
	_, err = tx.ExecContext(ctx, "SELECT pg_advisory_xact_lock($1)", lockKey)
	if err != nil {
		return "", fmt.Errorf("failed to acquire advisory lock: %w", err)
	}

	// Check if active chat room already exists between these users
	var roomID string
	checkQuery := `
		SELECT id::text FROM chat_rooms
		WHERE ((initiator_id = $1 AND acceptor_id = $2) OR (initiator_id = $2 AND acceptor_id = $1))
		  AND is_active = TRUE
		LIMIT 1`
	err = tx.QueryRowContext(ctx, checkQuery, u1, u2).Scan(&roomID)
	if err == nil {
		// Room exists, commit and return
		if err := tx.Commit(); err != nil {
			return "", fmt.Errorf("failed to commit transaction: %w", err)
		}
		return roomID, nil
	} else if err != sql.ErrNoRows {
		return "", fmt.Errorf("failed to check existing room: %w", err)
	}

	// Verify both users actually exist in the database (Participant existence validation)
	var count int
	verifyQuery := "SELECT COUNT(*) FROM users WHERE id = $1 OR id = $2"
	err = tx.QueryRowContext(ctx, verifyQuery, u1, u2).Scan(&count)
	if err != nil {
		return "", fmt.Errorf("failed to verify users existence: %w", err)
	}
	if count < 2 {
		return "", fmt.Errorf("one or both users do not exist: count=%d", count)
	}

	// Insert the new active room
	insertQuery := `
		INSERT INTO chat_rooms (initiator_id, acceptor_id, is_active)
		VALUES ($1, $2, TRUE)
		RETURNING id::text`
	err = tx.QueryRowContext(ctx, insertQuery, u1, u2).Scan(&roomID)
	if err != nil {
		return "", fmt.Errorf("failed to create chat room: %w", err)
	}

	// Commit transaction
	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("failed to commit transaction: %w", err)
	}

	return roomID, nil
}

