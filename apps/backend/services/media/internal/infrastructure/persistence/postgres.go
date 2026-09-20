package persistence

import (
	"context"
	"database/sql"

	"nearby/backend/services/media/internal/domain"
)

// PostgresMetadataRepository implements domain.MetadataRepository.
type PostgresMetadataRepository struct {
	db *sql.DB
}

// NewPostgresMetadataRepository creates a new PostgresMetadataRepository and runs self-healing schema checks.
func NewPostgresMetadataRepository(db *sql.DB) *PostgresMetadataRepository {
	query := `
	CREATE TABLE IF NOT EXISTS media_metadata (
		id UUID NOT NULL PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		content_type VARCHAR(100) NOT NULL,
		size BIGINT NOT NULL,
		s3_key VARCHAR(500) NOT NULL,
		owner_id UUID NOT NULL,
		room_id UUID,
		message_id UUID,
		is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
		deleted_at TIMESTAMPTZ,
		created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
	);`
	_, _ = db.Exec(query)

	// Self-healing: ensure room_id, message_id, is_deleted, deleted_at columns exist
	_, _ = db.Exec(`ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS room_id UUID;`)
	_, _ = db.Exec(`ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS message_id UUID;`)
	_, _ = db.Exec(`ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;`)
	_, _ = db.Exec(`ALTER TABLE media_metadata ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;`)

	return &PostgresMetadataRepository{db: db}
}

// SaveMetadata stores file attachment details in PostgreSQL.
func (r *PostgresMetadataRepository) SaveMetadata(ctx context.Context, meta *domain.FileMetadata) error {
	query := `
		INSERT INTO media_metadata (id, name, content_type, size, s3_key, owner_id, room_id, message_id, is_deleted, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, '')::uuid, NULLIF($8, '')::uuid, $9, $10)`
	_, err := r.db.ExecContext(ctx, query, meta.ID, meta.Name, meta.ContentType, meta.Size, meta.S3Key, meta.OwnerID, meta.RoomID, meta.MessageID, meta.IsDeleted, meta.CreatedAt)
	return err
}

// GetMetadata retrieves file attachment details from PostgreSQL (if not deleted).
func (r *PostgresMetadataRepository) GetMetadata(ctx context.Context, id string) (*domain.FileMetadata, error) {
	query := `
		SELECT id::text, name, content_type, size, s3_key, owner_id::text,
		       COALESCE(room_id::text, ''), COALESCE(message_id::text, ''),
		       is_deleted, deleted_at, created_at
		FROM media_metadata
		WHERE id = $1 AND is_deleted = FALSE`
	var meta domain.FileMetadata
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&meta.ID, &meta.Name, &meta.ContentType, &meta.Size, &meta.S3Key, &meta.OwnerID,
		&meta.RoomID, &meta.MessageID,
		&meta.IsDeleted, &meta.DeletedAt, &meta.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &meta, nil
}

// DeleteMetadata marks media metadata as deleted in PostgreSQL.
func (r *PostgresMetadataRepository) DeleteMetadata(ctx context.Context, id string) error {
	query := `
		UPDATE media_metadata
		SET is_deleted = TRUE, deleted_at = CURRENT_TIMESTAMP
		WHERE id = $1 AND is_deleted = FALSE`
	_, err := r.db.ExecContext(ctx, query, id)
	return err
}

// IsUserInRoom verifies whether userID is an active participant in roomID.
func (r *PostgresMetadataRepository) IsUserInRoom(ctx context.Context, userID, roomID string) (bool, error) {
	if userID == "" || roomID == "" {
		return false, nil
	}
	query := `
		SELECT is_active 
		FROM chat_rooms 
		WHERE id = $1::uuid AND (initiator_id = $2::uuid OR acceptor_id = $2::uuid)`
	var isActive bool
	err := r.db.QueryRowContext(ctx, query, roomID, userID).Scan(&isActive)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return isActive, nil
}

// IsMessageActiveInRoom verifies that messageID belongs to roomID and is not deleted.
func (r *PostgresMetadataRepository) IsMessageActiveInRoom(ctx context.Context, messageID, roomID string) (bool, error) {
	if messageID == "" || roomID == "" {
		return false, nil
	}
	query := `
		SELECT is_deleted 
		FROM messages 
		WHERE id = $1::uuid AND room_id = $2::uuid`
	var isDeleted bool
	err := r.db.QueryRowContext(ctx, query, messageID, roomID).Scan(&isDeleted)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, sql.ErrNoRows
		}
		return false, err
	}
	return !isDeleted, nil
}

