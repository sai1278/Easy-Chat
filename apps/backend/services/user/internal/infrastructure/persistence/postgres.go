package persistence

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// UserRepository handles SQL profile persistence commands.
type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	// Auto-migrate users table columns if not exists
	_, _ = db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id VARCHAR(255) PRIMARY KEY,
			pseudonym VARCHAR(255) NOT NULL,
			device_id VARCHAR(255) NOT NULL,
			role VARCHAR(50) DEFAULT 'user',
			display_name VARCHAR(255) DEFAULT '',
			avatar_url TEXT DEFAULT '',
			bio TEXT DEFAULT '',
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
		);
		ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(255) DEFAULT '';
		ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT DEFAULT '';
		ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT '';
		ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
	`)
	return &UserRepository{db: db}
}

// UserProfile represents the profile data returned to clients.
type UserProfile struct {
	ID          string    `json:"id"`
	Pseudonym   string    `json:"pseudonym"`
	DeviceID    string    `json:"device_id"`
	Role        string    `json:"role"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	Bio         string    `json:"bio"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// GetUserByID queries user profile columns.
func (r *UserRepository) GetUserByID(ctx context.Context, id string) (*UserProfile, error) {
	query := `SELECT id, pseudonym, device_id, role, COALESCE(display_name, ''), COALESCE(avatar_url, ''), COALESCE(bio, ''), COALESCE(updated_at, NOW()) FROM users WHERE id = $1`
	var profile UserProfile
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&profile.ID,
		&profile.Pseudonym,
		&profile.DeviceID,
		&profile.Role,
		&profile.DisplayName,
		&profile.AvatarURL,
		&profile.Bio,
		&profile.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("query user by id: %w", err)
	}
	return &profile, nil
}

// UpdateProfile updates user profile metadata in PostgreSQL.
func (r *UserRepository) UpdateProfile(ctx context.Context, id, displayName, avatarURL, bio string) (*UserProfile, error) {
	query := `
		UPDATE users 
		SET display_name = $1, avatar_url = $2, bio = $3, updated_at = NOW() 
		WHERE id = $4 
		RETURNING id, pseudonym, device_id, role, COALESCE(display_name, ''), COALESCE(avatar_url, ''), COALESCE(bio, ''), updated_at
	`
	var profile UserProfile
	err := r.db.QueryRowContext(ctx, query, displayName, avatarURL, bio, id).Scan(
		&profile.ID,
		&profile.Pseudonym,
		&profile.DeviceID,
		&profile.Role,
		&profile.DisplayName,
		&profile.AvatarURL,
		&profile.Bio,
		&profile.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("update user profile: %w", err)
	}
	return &profile, nil
}
