package persistence

import (
	"context"
	"database/sql"
	"time"

	"github.com/lib/pq"
	"nearby/backend/services/nearby/internal/domain"
	"nearby/backend/shared/geo"
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
		SELECT u.id::text, 
		       COALESCE(p.pseudonym, u.pseudonym), 
		       COALESCE(u.display_name, ''), 
		       COALESCE(u.avatar_url, ''), 
		       COALESCE(u.bio, ''), 
		       COALESCE(p.avatar_id, 0), 
		       u.status, 
		       COALESCE(pr.is_visible, TRUE)
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
		if err := rows.Scan(&m.UserID, &m.Pseudonym, &m.DisplayName, &m.AvatarURL, &m.Bio, &m.AvatarID, &m.Status, &m.IsVisible); err != nil {
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

// UpsertUserLocation persists the authoritative user location in the PostgreSQL user_locations table.
func (r *PostgresUserRepository) UpsertUserLocation(ctx context.Context, userID string, lat, lon float64, accuracy float64, updatedAt ...time.Time) error {
	updateTime := time.Now().UTC()
	if len(updatedAt) > 0 && !updatedAt[0].IsZero() {
		updateTime = updatedAt[0].UTC()
	}

	query := `
		INSERT INTO user_locations (user_id, latitude, longitude, accuracy_meters, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id) DO UPDATE
		SET latitude = EXCLUDED.latitude,
		    longitude = EXCLUDED.longitude,
		    accuracy_meters = EXCLUDED.accuracy_meters,
		    updated_at = EXCLUDED.updated_at`

	_, err := r.db.ExecContext(ctx, query, userID, lat, lon, accuracy, updateTime)
	return err
}

// GetUserLocation retrieves authoritative user location from the PostgreSQL user_locations table.
func (r *PostgresUserRepository) GetUserLocation(ctx context.Context, userID string) (*geo.LocationData, error) {
	query := `
		SELECT latitude, longitude, accuracy_meters, updated_at
		FROM user_locations
		WHERE user_id = $1`

	var loc geo.LocationData
	loc.UserID = userID
	err := r.db.QueryRowContext(ctx, query, userID).Scan(
		&loc.Latitude,
		&loc.Longitude,
		&loc.AccuracyMeters,
		&loc.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &loc, nil
}

