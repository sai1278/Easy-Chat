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

// GetMessageByID retrieves a single message by ID and RoomID.
func (r *PostgresChatRepository) GetMessageByID(ctx context.Context, messageID, roomID string) (*domain.Message, error) {
	query := `
		SELECT id::text, room_id::text, sender_id::text, encrypted_payload, is_deleted, deleted_at, created_at
		FROM messages
		WHERE id = $1 AND room_id = $2`
	var msg domain.Message
	err := r.db.QueryRowContext(ctx, query, messageID, roomID).Scan(
		&msg.ID, &msg.RoomID, &msg.SenderID, &msg.EncryptedPayload, &msg.IsDeleted, &msg.DeletedAt, &msg.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &msg, nil
}

// DeleteMessageForEveryone marks a message as deleted, nullifies the ciphertext payload, and stamps deleted_at.
func (r *PostgresChatRepository) DeleteMessageForEveryone(ctx context.Context, messageID, roomID, senderID string) error {
	query := `
		UPDATE messages
		SET is_deleted = TRUE, deleted_at = CURRENT_TIMESTAMP, encrypted_payload = E'\\x'
		WHERE id = $1 AND room_id = $2 AND sender_id = $3 AND is_deleted = FALSE`
	res, err := r.db.ExecContext(ctx, query, messageID, roomID, senderID)
	if err != nil {
		return err
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return fmt.Errorf("message not found, already deleted, or unauthorized deletion attempt")
	}
	return nil
}

// GetDeletedMessagesSince retrieves IDs of messages deleted since reconnect timestamp for offline synchronization.
func (r *PostgresChatRepository) GetDeletedMessagesSince(ctx context.Context, roomIDs []string, since time.Time) ([]string, error) {
	if len(roomIDs) == 0 {
		return []string{}, nil
	}

	query := `
		SELECT id::text
		FROM messages
		WHERE room_id = ANY($1) AND deleted_at > $2 AND is_deleted = TRUE
		ORDER BY deleted_at ASC`
	rows, err := r.db.QueryContext(ctx, query, pq.Array(roomIDs), since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var deletedIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		deletedIDs = append(deletedIDs, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetDeletedMessagesSince rows: %w", err)
	}
	return deletedIDs, nil
}

// GetRoomMessagesSince retrieves active room messages since a specific timestamp for reconnect recovery.
func (r *PostgresChatRepository) GetRoomMessagesSince(ctx context.Context, roomID string, since time.Time) ([]*domain.Message, error) {
	query := `
		SELECT id::text, room_id::text, sender_id::text, encrypted_payload, is_deleted, deleted_at, created_at
		FROM messages
		WHERE room_id = $1 AND created_at > $2 AND is_deleted = FALSE
		ORDER BY created_at ASC`
	rows, err := r.db.QueryContext(ctx, query, roomID, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*domain.Message
	for rows.Next() {
		var msg domain.Message
		if err := rows.Scan(&msg.ID, &msg.RoomID, &msg.SenderID, &msg.EncryptedPayload, &msg.IsDeleted, &msg.DeletedAt, &msg.CreatedAt); err != nil {
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

// GetRoomsMessagesSince retrieves active messages since a specific timestamp across multiple rooms in a single query with pagination.
func (r *PostgresChatRepository) GetRoomsMessagesSince(ctx context.Context, roomIDs []string, since time.Time, limit, offset int) ([]*domain.Message, error) {
	if len(roomIDs) == 0 {
		return []*domain.Message{}, nil
	}

	query := `
		SELECT id::text, room_id::text, sender_id::text, encrypted_payload, is_deleted, deleted_at, created_at
		FROM messages
		WHERE room_id = ANY($1) AND created_at > $2 AND is_deleted = FALSE
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
		if err := rows.Scan(&msg.ID, &msg.RoomID, &msg.SenderID, &msg.EncryptedPayload, &msg.IsDeleted, &msg.DeletedAt, &msg.CreatedAt); err != nil {
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

// SaveCryptoIdentity upserts public identity and signed prekey for E2EE session agreement.
func (r *PostgresChatRepository) SaveCryptoIdentity(ctx context.Context, identity *domain.UserCryptoIdentity) error {
	query := `
		INSERT INTO user_crypto_identities (user_id, identity_key_pub, signed_prekey_pub, signed_prekey_sig, created_at, updated_at)
		VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		ON CONFLICT (user_id) DO UPDATE SET
			identity_key_pub = EXCLUDED.identity_key_pub,
			signed_prekey_pub = EXCLUDED.signed_prekey_pub,
			signed_prekey_sig = EXCLUDED.signed_prekey_sig,
			updated_at = CURRENT_TIMESTAMP`
	_, err := r.db.ExecContext(ctx, query, identity.UserID, identity.IdentityKeyPub, identity.SignedPrekeyPub, identity.SignedPrekeySig)
	return err
}

// GetCryptoIdentity retrieves public identity and signed prekey for a user.
func (r *PostgresChatRepository) GetCryptoIdentity(ctx context.Context, userID string) (*domain.UserCryptoIdentity, error) {
	query := `
		SELECT user_id::text, identity_key_pub, signed_prekey_pub, signed_prekey_sig, created_at, updated_at
		FROM user_crypto_identities
		WHERE user_id = $1`
	var id domain.UserCryptoIdentity
	err := r.db.QueryRowContext(ctx, query, userID).Scan(
		&id.UserID, &id.IdentityKeyPub, &id.SignedPrekeyPub, &id.SignedPrekeySig, &id.CreatedAt, &id.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &id, nil
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

// IsRoomActive checks if a chat room is currently active.
func (r *PostgresRoomRepository) IsRoomActive(ctx context.Context, roomID string) (bool, error) {
	query := `SELECT is_active FROM chat_rooms WHERE id = $1`
	var isActive bool
	err := r.db.QueryRowContext(ctx, query, roomID).Scan(&isActive)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("IsRoomActive: %w", err)
	}
	return isActive, nil
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

// PostgresRequestRepository implements domain.RequestRepository for PostgreSQL.
type PostgresRequestRepository struct {
	db *sql.DB
}

// NewPostgresRequestRepository creates a new PostgresRequestRepository.
func NewPostgresRequestRepository(db *sql.DB) *PostgresRequestRepository {
	return &PostgresRequestRepository{db: db}
}

// CreateRequest creates a new chat request or returns an existing valid request.
func (r *PostgresRequestRepository) CreateRequest(ctx context.Context, senderID, recipientID string) (*domain.ChatRequest, error) {
	if senderID == recipientID {
		return nil, fmt.Errorf("sender and recipient cannot be the same user")
	}

	// Verify both users exist
	var count int
	verifyQuery := "SELECT COUNT(*) FROM users WHERE id = $1::uuid OR id = $2::uuid"
	err := r.db.QueryRowContext(ctx, verifyQuery, senderID, recipientID).Scan(&count)
	if err != nil {
		return nil, fmt.Errorf("failed to verify users: %w", err)
	}
	if count < 2 {
		return nil, fmt.Errorf("one or both users do not exist: count=%d", count)
	}

	// Check if a request already exists between these two users
	var existing domain.ChatRequest
	var roomIDStr sql.NullString
	var statusStr string
	var respTime sql.NullTime
	checkQuery := `
		SELECT r.id::text, r.sender_id::text, r.recipient_id::text, COALESCE(r.room_id::text, ''), r.status, r.created_at, r.updated_at, r.responded_at,
		       COALESCE(u.display_name, u.pseudonym, ''), COALESCE(u.pseudonym, ''), COALESCE(u.avatar_url, ''), COALESCE(u.bio, '')
		FROM chat_requests r
		JOIN users u ON u.id = r.sender_id
		WHERE (r.sender_id = $1::uuid AND r.recipient_id = $2::uuid) OR (r.sender_id = $2::uuid AND r.recipient_id = $1::uuid)
		ORDER BY r.created_at DESC
		LIMIT 1`
	err = r.db.QueryRowContext(ctx, checkQuery, senderID, recipientID).Scan(
		&existing.ID, &existing.SenderID, &existing.RecipientID, &roomIDStr, &statusStr, &existing.CreatedAt, &existing.UpdatedAt, &respTime,
		&existing.SenderDisplayName, &existing.SenderUsername, &existing.SenderAvatarURL, &existing.SenderBio,
	)
	if err == nil {
		existing.Status = domain.ChatRequestStatus(statusStr)
		if roomIDStr.Valid {
			existing.RoomID = roomIDStr.String
		}
		if respTime.Valid {
			t := respTime.Time
			existing.RespondedAt = &t
		}
		// If already PENDING, return existing (prevents duplicate spam)
		if existing.Status == domain.RequestStatusPending {
			return &existing, nil
		}
		// If already ACCEPTED, return existing
		if existing.Status == domain.RequestStatusAccepted {
			return &existing, nil
		}
		// If DENIED or CANCELLED, allow creating a new request
	}

	// Insert new PENDING request
	var newReq domain.ChatRequest
	insertQuery := `
		INSERT INTO chat_requests (sender_id, recipient_id, status)
		VALUES ($1::uuid, $2::uuid, 'PENDING')
		RETURNING id::text, created_at, updated_at`
	err = r.db.QueryRowContext(ctx, insertQuery, senderID, recipientID).Scan(&newReq.ID, &newReq.CreatedAt, &newReq.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to create chat request: %w", err)
	}

	newReq.SenderID = senderID
	newReq.RecipientID = recipientID
	newReq.Status = domain.RequestStatusPending

	// Fetch sender profile details
	_ = r.db.QueryRowContext(ctx, `
		SELECT COALESCE(display_name, pseudonym, ''), COALESCE(pseudonym, ''), COALESCE(avatar_url, ''), COALESCE(bio, '')
		FROM users WHERE id = $1::uuid`, senderID).Scan(
		&newReq.SenderDisplayName, &newReq.SenderUsername, &newReq.SenderAvatarURL, &newReq.SenderBio,
	)

	return &newReq, nil
}

// GetPendingRequestsForUser retrieves all incoming pending chat requests for a user.
func (r *PostgresRequestRepository) GetPendingRequestsForUser(ctx context.Context, recipientID string) ([]*domain.ChatRequest, error) {
	query := `
		SELECT r.id::text, r.sender_id::text, r.recipient_id::text, COALESCE(r.room_id::text, ''), r.status, r.created_at, r.updated_at, r.responded_at,
		       COALESCE(u.display_name, u.pseudonym, ''), COALESCE(u.pseudonym, ''), COALESCE(u.avatar_url, ''), COALESCE(u.bio, '')
		FROM chat_requests r
		JOIN users u ON u.id = r.sender_id
		WHERE r.recipient_id = $1::uuid AND r.status = 'PENDING'
		ORDER BY r.created_at DESC`
	rows, err := r.db.QueryContext(ctx, query, recipientID)
	if err != nil {
		return nil, fmt.Errorf("GetPendingRequestsForUser: %w", err)
	}
	defer rows.Close()

	var list []*domain.ChatRequest
	for rows.Next() {
		var req domain.ChatRequest
		var roomIDStr sql.NullString
		var statusStr string
		var respTime sql.NullTime
		if err := rows.Scan(
			&req.ID, &req.SenderID, &req.RecipientID, &roomIDStr, &statusStr, &req.CreatedAt, &req.UpdatedAt, &respTime,
			&req.SenderDisplayName, &req.SenderUsername, &req.SenderAvatarURL, &req.SenderBio,
		); err != nil {
			return nil, err
		}
		req.Status = domain.ChatRequestStatus(statusStr)
		if roomIDStr.Valid {
			req.RoomID = roomIDStr.String
		}
		if respTime.Valid {
			t := respTime.Time
			req.RespondedAt = &t
		}
		list = append(list, &req)
	}
	return list, rows.Err()
}

// GetRequestByID retrieves a chat request by ID.
func (r *PostgresRequestRepository) GetRequestByID(ctx context.Context, requestID string) (*domain.ChatRequest, error) {
	query := `
		SELECT r.id::text, r.sender_id::text, r.recipient_id::text, COALESCE(r.room_id::text, ''), r.status, r.created_at, r.updated_at, r.responded_at,
		       COALESCE(u.display_name, u.pseudonym, ''), COALESCE(u.pseudonym, ''), COALESCE(u.avatar_url, ''), COALESCE(u.bio, '')
		FROM chat_requests r
		JOIN users u ON u.id = r.sender_id
		WHERE r.id = $1::uuid`
	var req domain.ChatRequest
	var roomIDStr sql.NullString
	var statusStr string
	var respTime sql.NullTime
	err := r.db.QueryRowContext(ctx, query, requestID).Scan(
		&req.ID, &req.SenderID, &req.RecipientID, &roomIDStr, &statusStr, &req.CreatedAt, &req.UpdatedAt, &respTime,
		&req.SenderDisplayName, &req.SenderUsername, &req.SenderAvatarURL, &req.SenderBio,
	)
	if err != nil {
		return nil, err
	}
	req.Status = domain.ChatRequestStatus(statusStr)
	if roomIDStr.Valid {
		req.RoomID = roomIDStr.String
	}
	if respTime.Valid {
		t := respTime.Time
		req.RespondedAt = &t
	}
	return &req, nil
}

// GetRequestBetweenUsers retrieves the latest chat request between two users.
func (r *PostgresRequestRepository) GetRequestBetweenUsers(ctx context.Context, userA, userB string) (*domain.ChatRequest, error) {
	query := `
		SELECT r.id::text, r.sender_id::text, r.recipient_id::text, COALESCE(r.room_id::text, ''), r.status, r.created_at, r.updated_at, r.responded_at,
		       COALESCE(u.display_name, u.pseudonym, ''), COALESCE(u.pseudonym, ''), COALESCE(u.avatar_url, ''), COALESCE(u.bio, '')
		FROM chat_requests r
		JOIN users u ON u.id = r.sender_id
		WHERE (r.sender_id = $1::uuid AND r.recipient_id = $2::uuid) OR (r.sender_id = $2::uuid AND r.recipient_id = $1::uuid)
		ORDER BY r.created_at DESC
		LIMIT 1`
	var req domain.ChatRequest
	var roomIDStr sql.NullString
	var statusStr string
	var respTime sql.NullTime
	err := r.db.QueryRowContext(ctx, query, userA, userB).Scan(
		&req.ID, &req.SenderID, &req.RecipientID, &roomIDStr, &statusStr, &req.CreatedAt, &req.UpdatedAt, &respTime,
		&req.SenderDisplayName, &req.SenderUsername, &req.SenderAvatarURL, &req.SenderBio,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	req.Status = domain.ChatRequestStatus(statusStr)
	if roomIDStr.Valid {
		req.RoomID = roomIDStr.String
	}
	if respTime.Valid {
		t := respTime.Time
		req.RespondedAt = &t
	}
	return &req, nil
}

// AcceptRequest marks a request as ACCEPTED and creates/activates the associated chat room atomically.
func (r *PostgresRequestRepository) AcceptRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	var req domain.ChatRequest
	var roomIDStr sql.NullString
	var statusStr string
	var respTime sql.NullTime
	query := `
		SELECT id::text, sender_id::text, recipient_id::text, COALESCE(room_id::text, ''), status, created_at, updated_at, responded_at
		FROM chat_requests
		WHERE id = $1::uuid
		FOR UPDATE`
	err = tx.QueryRowContext(ctx, query, requestID).Scan(
		&req.ID, &req.SenderID, &req.RecipientID, &roomIDStr, &statusStr, &req.CreatedAt, &req.UpdatedAt, &respTime,
	)
	if err != nil {
		return nil, fmt.Errorf("chat request not found: %w", err)
	}
	req.Status = domain.ChatRequestStatus(statusStr)
	if roomIDStr.Valid {
		req.RoomID = roomIDStr.String
	}
	if respTime.Valid {
		t := respTime.Time
		req.RespondedAt = &t
	}

	// 1. Authorization: Only recipient can accept
	if req.RecipientID != recipientID {
		return nil, fmt.Errorf("unauthorized: only the recipient can accept this chat request")
	}

	// 2. Request state validation
	if req.Status == domain.RequestStatusAccepted {
		return nil, fmt.Errorf("request already accepted")
	}
	if req.Status == domain.RequestStatusDenied {
		return nil, fmt.Errorf("cannot accept an already denied request")
	}
	if req.Status != domain.RequestStatusPending {
		return nil, fmt.Errorf("cannot accept request in %s status", req.Status)
	}

	// 3. Create or reactivate active chat room
	var roomID string
	findRoom := `
		SELECT id::text FROM chat_rooms
		WHERE ((initiator_id = $1::uuid AND acceptor_id = $2::uuid) OR (initiator_id = $2::uuid AND acceptor_id = $1::uuid))
		LIMIT 1`
	err = tx.QueryRowContext(ctx, findRoom, req.SenderID, req.RecipientID).Scan(&roomID)
	if err == nil {
		// Existing room: mark active
		_, err = tx.ExecContext(ctx, "UPDATE chat_rooms SET is_active = TRUE, closed_at = NULL WHERE id = $1::uuid", roomID)
		if err != nil {
			return nil, fmt.Errorf("failed to reactivate room: %w", err)
		}
	} else {
		// New room
		insertRoom := `
			INSERT INTO chat_rooms (initiator_id, acceptor_id, is_active)
			VALUES ($1::uuid, $2::uuid, TRUE)
			RETURNING id::text`
		err = tx.QueryRowContext(ctx, insertRoom, req.SenderID, req.RecipientID).Scan(&roomID)
		if err != nil {
			return nil, fmt.Errorf("failed to create active room: %w", err)
		}
	}

	// 4. Update request status to ACCEPTED
	now := time.Now()
	updateQuery := `
		UPDATE chat_requests
		SET status = 'ACCEPTED', room_id = $1::uuid, responded_at = $2, updated_at = $2
		WHERE id = $3::uuid
		RETURNING updated_at`
	err = tx.QueryRowContext(ctx, updateQuery, roomID, now, requestID).Scan(&req.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to update request to ACCEPTED: %w", err)
	}
	req.RoomID = roomID
	req.Status = domain.RequestStatusAccepted
	req.RespondedAt = &now

	// Fetch sender profile details
	_ = tx.QueryRowContext(ctx, `
		SELECT COALESCE(display_name, pseudonym, ''), COALESCE(pseudonym, ''), COALESCE(avatar_url, ''), COALESCE(bio, '')
		FROM users WHERE id = $1::uuid`, req.SenderID).Scan(
		&req.SenderDisplayName, &req.SenderUsername, &req.SenderAvatarURL, &req.SenderBio,
	)

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit accept transaction: %w", err)
	}

	return &req, nil
}

// DenyRequest marks a request as DENIED and ensures any associated room is inactive.
func (r *PostgresRequestRepository) DenyRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	var req domain.ChatRequest
	var roomIDStr sql.NullString
	var statusStr string
	var respTime sql.NullTime
	query := `
		SELECT id::text, sender_id::text, recipient_id::text, COALESCE(room_id::text, ''), status, created_at, updated_at, responded_at
		FROM chat_requests
		WHERE id = $1::uuid
		FOR UPDATE`
	err = tx.QueryRowContext(ctx, query, requestID).Scan(
		&req.ID, &req.SenderID, &req.RecipientID, &roomIDStr, &statusStr, &req.CreatedAt, &req.UpdatedAt, &respTime,
	)
	if err != nil {
		return nil, fmt.Errorf("chat request not found: %w", err)
	}
	req.Status = domain.ChatRequestStatus(statusStr)
	if roomIDStr.Valid {
		req.RoomID = roomIDStr.String
	}
	if respTime.Valid {
		t := respTime.Time
		req.RespondedAt = &t
	}

	// 1. Authorization: Only recipient can deny
	if req.RecipientID != recipientID {
		return nil, fmt.Errorf("unauthorized: only the recipient can deny this chat request")
	}

	// 2. Request state validation
	if req.Status == domain.RequestStatusAccepted {
		return nil, fmt.Errorf("cannot deny an already accepted request")
	}
	if req.Status == domain.RequestStatusDenied {
		return nil, fmt.Errorf("request already denied")
	}
	if req.Status != domain.RequestStatusPending {
		return nil, fmt.Errorf("cannot deny request in %s status", req.Status)
	}

	// 3. Deactivate any room associated with these users
	_, _ = tx.ExecContext(ctx, `
		UPDATE chat_rooms
		SET is_active = FALSE, closed_at = CURRENT_TIMESTAMP
		WHERE ((initiator_id = $1::uuid AND acceptor_id = $2::uuid) OR (initiator_id = $2::uuid AND acceptor_id = $1::uuid))`,
		req.SenderID, req.RecipientID)

	// 4. Update request status to DENIED
	now := time.Now()
	updateQuery := `
		UPDATE chat_requests
		SET status = 'DENIED', responded_at = $1, updated_at = $1
		WHERE id = $2::uuid
		RETURNING updated_at`
	err = tx.QueryRowContext(ctx, updateQuery, now, requestID).Scan(&req.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to update request to DENIED: %w", err)
	}
	req.Status = domain.RequestStatusDenied
	req.RespondedAt = &now

	// Fetch sender profile details
	_ = tx.QueryRowContext(ctx, `
		SELECT COALESCE(display_name, pseudonym, ''), COALESCE(pseudonym, ''), COALESCE(avatar_url, ''), COALESCE(bio, '')
		FROM users WHERE id = $1::uuid`, req.SenderID).Scan(
		&req.SenderDisplayName, &req.SenderUsername, &req.SenderAvatarURL, &req.SenderBio,
	)

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit deny transaction: %w", err)
	}

	return &req, nil
}

// IsRoomActiveAndAccepted checks whether a room exists, is active, and is not blocked by a denied/pending request.
func (r *PostgresRequestRepository) IsRoomActiveAndAccepted(ctx context.Context, roomID string) (bool, error) {
	query := `
		SELECT cr.is_active, COALESCE(r.status, 'ACCEPTED')
		FROM chat_rooms cr
		LEFT JOIN chat_requests r ON r.room_id = cr.id
		WHERE cr.id = $1::uuid
		ORDER BY r.created_at DESC NULLS LAST
		LIMIT 1`
	var isActive bool
	var status string
	err := r.db.QueryRowContext(ctx, query, roomID).Scan(&isActive, &status)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("IsRoomActiveAndAccepted: %w", err)
	}
	if !isActive || status == string(domain.RequestStatusDenied) || status == string(domain.RequestStatusPending) {
		return false, nil
	}
	return true, nil
}

