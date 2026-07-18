package persistence

import (
	"context"
	"database/sql"
	"fmt"
)

// UserRepository handles SQL profile persistence commands.
type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

// UserProfile represents the profile data returned to clients.
type UserProfile struct {
	ID        string `json:"id"`
	Pseudonym string `json:"pseudonym"`
	DeviceID  string `json:"device_id"`
	Role      string `json:"role"`
}

// GetUserByID queries user profile columns.
func (r *UserRepository) GetUserByID(ctx context.Context, id string) (*UserProfile, error) {
	query := `SELECT id, pseudonym, device_id, role FROM users WHERE id = $1`
	var profile UserProfile
	err := r.db.QueryRowContext(ctx, query, id).Scan(&profile.ID, &profile.Pseudonym, &profile.DeviceID, &profile.Role)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("query user by id: %w", err)
	}
	return &profile, nil
}
