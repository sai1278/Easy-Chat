package persistence

import (
	"context"
	"database/sql"

	"nearby/backend/services/notification/internal/domain"
)

// PostgresPreferenceRepository implements domain.PreferenceRepository.
type PostgresPreferenceRepository struct {
	db *sql.DB
}

// NewPostgresPreferenceRepository creates a new PostgresPreferenceRepository and runs self-healing schema creation.
func NewPostgresPreferenceRepository(db *sql.DB) *PostgresPreferenceRepository {
	query := `
	CREATE TABLE IF NOT EXISTS notification_preferences (
		user_id UUID NOT NULL PRIMARY KEY,
		enable_push BOOLEAN NOT NULL DEFAULT TRUE,
		quiet_hours_start VARCHAR(5) NOT NULL DEFAULT '22:00',
		quiet_hours_end VARCHAR(5) NOT NULL DEFAULT '08:00'
	);`
	_, _ = db.Exec(query)

	return &PostgresPreferenceRepository{db: db}
}

// SavePreference persists user settings in PostgreSQL.
func (r *PostgresPreferenceRepository) SavePreference(ctx context.Context, pref *domain.NotificationPreference) error {
	query := `
		INSERT INTO notification_preferences (user_id, enable_push, quiet_hours_start, quiet_hours_end)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE
		SET enable_push = EXCLUDED.enable_push,
		    quiet_hours_start = EXCLUDED.quiet_hours_start,
		    quiet_hours_end = EXCLUDED.quiet_hours_end`
	_, err := r.db.ExecContext(ctx, query, pref.UserID, pref.EnablePush, pref.QuietHoursStart, pref.QuietHoursEnd)
	return err
}

// GetPreference fetches user settings from PostgreSQL.
func (r *PostgresPreferenceRepository) GetPreference(ctx context.Context, userID string) (*domain.NotificationPreference, error) {
	query := `
		SELECT user_id::text, enable_push, quiet_hours_start, quiet_hours_end
		FROM notification_preferences
		WHERE user_id = $1`
	var pref domain.NotificationPreference
	err := r.db.QueryRowContext(ctx, query, userID).Scan(&pref.UserID, &pref.EnablePush, &pref.QuietHoursStart, &pref.QuietHoursEnd)
	if err != nil {
		if err == sql.ErrNoRows {
			// Return default configurations if user settings do not exist yet
			return &domain.NotificationPreference{
				UserID:          userID,
				EnablePush:      true,
				QuietHoursStart: "22:00",
				QuietHoursEnd:   "08:00",
			}, nil
		}
		return nil, err
	}
	return &pref, nil
}
