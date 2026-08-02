package persistence

import (
	"context"
	"database/sql"

	"github.com/lib/pq"
	"nearby/backend/services/nearby/internal/domain"
)

// PostgresUserRepository implements domain.UserRepository.
type PostgresUserRepository struct {
	db *sql.DB
}

// NewPostgresUserRepository creates a new PostgresUserRepository.
func NewPostgresUserRepository(db *sql.DB) *PostgresUserRepository {
	return &PostgresUserRepository{db: db}
}

// GetActiveUsersMetadata fetches user profiles, statuses, and visibility settings in bulk.
func (r *PostgresUserRepository) GetActiveUsersMetadata(ctx context.Context, userIDs []string) (map[string]*domain.UserMetadata, error) {
	if len(userIDs) == 0 {
		return make(map[string]*domain.UserMetadata), nil
	}

	query := `
		SELECT u.id::text, COALESCE(p.pseudonym, u.pseudonym), COALESCE(p.avatar_id, 0), u.status, COALESCE(pr.is_visible, TRUE)
		FROM users u
		LEFT JOIN profiles p ON u.id = p.user_id
		LEFT JOIN presence pr ON u.id = pr.user_id
		WHERE u.id = ANY($1) AND u.status = 'ACTIVE' AND COALESCE(pr.is_visible, TRUE) = TRUE`

	rows, err := r.db.QueryContext(ctx, query, pq.Array(userIDs))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	metadataMap := make(map[string]*domain.UserMetadata)
	for rows.Next() {
		var m domain.UserMetadata
		if err := rows.Scan(&m.UserID, &m.Pseudonym, &m.AvatarID, &m.Status, &m.IsVisible); err != nil {
			return nil, err
		}
		metadataMap[m.UserID] = &m
	}

	return metadataMap, nil
}

// GetBlockFilter retrieves user IDs that have blocked or been blocked by the requester.
func (r *PostgresUserRepository) GetBlockFilter(ctx context.Context, userID string) (map[string]bool, error) {
	query := `
		SELECT blocked_id::text FROM user_blocks WHERE blocker_id = $1
		UNION
		SELECT blocker_id::text FROM user_blocks WHERE blocked_id = $1`

	rows, err := r.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	blockMap := make(map[string]bool)
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		blockMap[id] = true
	}

	return blockMap, nil
}
