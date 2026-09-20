// Package persistence implements the auth domain repository interfaces against PostgreSQL.
// All query results check rows.Err() after iteration (fixes CRIT-15).
package persistence

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"nearby/backend/services/auth/internal/domain"
)

// PostgresUserRepository implements domain.UserRepository.
type PostgresUserRepository struct {
	db *sql.DB
}

// NewPostgresUserRepository creates a user repository backed by a *sql.DB.
func NewPostgresUserRepository(db *sql.DB) *PostgresUserRepository {
	return &PostgresUserRepository{db: db}
}

func (r *PostgresUserRepository) Create(ctx context.Context, u *domain.User) error {
	query := `
		INSERT INTO users (id, pseudonym, display_name, device_id, password_hash, role, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
	_, err := r.db.ExecContext(ctx, query,
		u.ID, u.Pseudonym, u.DisplayName, u.DeviceID, u.PasswordHash,
		string(u.Role), u.CreatedAt, u.UpdatedAt,
	)
	return err
}

func (r *PostgresUserRepository) GetByID(ctx context.Context, id string) (*domain.User, error) {
	query := `SELECT id, pseudonym, COALESCE(display_name, ''), device_id, password_hash, role, created_at, updated_at
	          FROM users WHERE id = $1`
	var u domain.User
	var roleStr string
	err := r.db.QueryRowContext(ctx, query, id).
		Scan(&u.ID, &u.Pseudonym, &u.DisplayName, &u.DeviceID, &u.PasswordHash, &roleStr, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("GetByID: %w", err)
	}
	u.Role = domain.Role(roleStr)
	return &u, nil
}

func (r *PostgresUserRepository) GetByDeviceID(ctx context.Context, deviceID string) (*domain.User, error) {
	query := `SELECT id, pseudonym, COALESCE(display_name, ''), device_id, password_hash, role, created_at, updated_at
	          FROM users WHERE device_id = $1`
	var u domain.User
	var roleStr string
	err := r.db.QueryRowContext(ctx, query, deviceID).
		Scan(&u.ID, &u.Pseudonym, &u.DisplayName, &u.DeviceID, &u.PasswordHash, &roleStr, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("GetByDeviceID: %w", err)
	}
	u.Role = domain.Role(roleStr)
	return &u, nil
}

// Delete removes the user record and revokes all associated sessions (fixes MED-19).
// Both operations are wrapped in a transaction to ensure atomicity.
func (r *PostgresUserRepository) Delete(ctx context.Context, id string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	// Revoke all sessions first so tokens become immediately invalid.
	if _, err := tx.ExecContext(ctx,
		`UPDATE user_sessions SET is_revoked = true WHERE user_id = $1`, id,
	); err != nil {
		return fmt.Errorf("revoke sessions: %w", err)
	}

	if _, err := tx.ExecContext(ctx, `DELETE FROM users WHERE id = $1`, id); err != nil {
		return fmt.Errorf("delete user: %w", err)
	}

	return tx.Commit()
}

// PostgresSessionRepository implements domain.SessionRepository.
type PostgresSessionRepository struct {
	db *sql.DB
}

// NewPostgresSessionRepository creates a session repository backed by a *sql.DB.
func NewPostgresSessionRepository(db *sql.DB) *PostgresSessionRepository {
	return &PostgresSessionRepository{db: db}
}

func (r *PostgresSessionRepository) Save(ctx context.Context, s *domain.Session) error {
	query := `
		INSERT INTO user_sessions
		    (id, user_id, device_id, refresh_token_hash, role, is_revoked, expires_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (created_at, id) DO UPDATE
		SET refresh_token_hash = EXCLUDED.refresh_token_hash,
		    is_revoked          = EXCLUDED.is_revoked,
		    expires_at          = EXCLUDED.expires_at,
		    updated_at          = EXCLUDED.updated_at`
	now := time.Now().UTC()
	_, err := r.db.ExecContext(ctx, query,
		s.ID, s.UserID, s.DeviceID, s.RefreshTokenHash, s.Role,
		s.IsRevoked, s.ExpiresAt, s.CreatedAt, now,
	)
	return err
}

func (r *PostgresSessionRepository) GetByID(ctx context.Context, id string) (*domain.Session, error) {
	query := `
		SELECT id, user_id, device_id, refresh_token_hash, role, is_revoked, expires_at, created_at
		FROM user_sessions WHERE id = $1`
	var s domain.Session
	err := r.db.QueryRowContext(ctx, query, id).
		Scan(&s.ID, &s.UserID, &s.DeviceID, &s.RefreshTokenHash, &s.Role,
			&s.IsRevoked, &s.ExpiresAt, &s.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("GetByID: %w", err)
	}
	return &s, nil
}

func (r *PostgresSessionRepository) GetByUserID(ctx context.Context, userID string) ([]*domain.Session, error) {
	query := `
		SELECT id, user_id, device_id, refresh_token_hash, role, is_revoked, expires_at, created_at
		FROM user_sessions WHERE user_id = $1`
	rows, err := r.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("GetByUserID query: %w", err)
	}
	defer rows.Close()

	var sessions []*domain.Session
	for rows.Next() {
		var s domain.Session
		if err := rows.Scan(&s.ID, &s.UserID, &s.DeviceID, &s.RefreshTokenHash, &s.Role,
			&s.IsRevoked, &s.ExpiresAt, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("GetByUserID scan: %w", err)
		}
		sessions = append(sessions, &s)
	}
	// CRIT-15: check for errors that occurred during row iteration.
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetByUserID rows: %w", err)
	}
	return sessions, nil
}

func (r *PostgresSessionRepository) RevokeSession(ctx context.Context, sessionID string) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE user_sessions SET is_revoked = true, updated_at = $2 WHERE id = $1`,
		sessionID, time.Now().UTC(),
	)
	return err
}

func (r *PostgresSessionRepository) RevokeAllSessionsForUser(ctx context.Context, userID string) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE user_sessions SET is_revoked = true, updated_at = $2 WHERE user_id = $1`,
		userID, time.Now().UTC(),
	)
	return err
}
