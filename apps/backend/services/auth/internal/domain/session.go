package domain

import "time"

// Session represents an active authenticated device session.
// RefreshTokenHash stores a bcrypt hash — never the raw token.
type Session struct {
	ID               string    `json:"id"`
	UserID           string    `json:"user_id"`
	DeviceID         string    `json:"device_id"`
	RefreshTokenHash string    `json:"-"`            // bcrypt hash, never serialised
	Role             string    `json:"role"`
	IsRevoked        bool      `json:"is_revoked"`
	ExpiresAt        time.Time `json:"expires_at"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}
