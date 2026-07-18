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
		created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
	);`
	_, _ = db.Exec(query)

	return &PostgresMetadataRepository{db: db}
}

// SaveMetadata stores file attachment details in PostgreSQL.
func (r *PostgresMetadataRepository) SaveMetadata(ctx context.Context, meta *domain.FileMetadata) error {
	query := `
		INSERT INTO media_metadata (id, name, content_type, size, s3_key, owner_id, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err := r.db.ExecContext(ctx, query, meta.ID, meta.Name, meta.ContentType, meta.Size, meta.S3Key, meta.OwnerID, meta.CreatedAt)
	return err
}

// GetMetadata retrieves file attachment details from PostgreSQL.
func (r *PostgresMetadataRepository) GetMetadata(ctx context.Context, id string) (*domain.FileMetadata, error) {
	query := `
		SELECT id::text, name, content_type, size, s3_key, owner_id::text, created_at
		FROM media_metadata
		WHERE id = $1`
	var meta domain.FileMetadata
	err := r.db.QueryRowContext(ctx, query, id).Scan(&meta.ID, &meta.Name, &meta.ContentType, &meta.Size, &meta.S3Key, &meta.OwnerID, &meta.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &meta, nil
}
