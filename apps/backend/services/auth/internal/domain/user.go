package domain

import (
	"fmt"
	"time"
)

// Role is the permission level associated with a user account.
type Role string

const (
	RoleAnonymousUser Role = "anonymous_user"
	RoleModerator     Role = "moderator"
	RoleAdministrator Role = "administrator"
)

// User represents the central profile account within the system.
type User struct {
	ID           string    `json:"id"`
	Pseudonym    string    `json:"pseudonym"`
	DeviceID     string    `json:"device_id"`
	PasswordHash string    `json:"-"` // bcrypt hash — never serialised
	Role         Role      `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Validate enforces domain invariants before persistence (fixes LOW-06).
func (u *User) Validate() error {
	if u.ID == "" {
		return fmt.Errorf("%w: user id is required", ErrInvalidInput)
	}
	if u.DeviceID == "" {
		return fmt.Errorf("%w: device_id is required", ErrInvalidInput)
	}
	if u.Pseudonym == "" {
		return fmt.Errorf("%w: pseudonym is required", ErrInvalidInput)
	}
	if u.Role == "" {
		return fmt.Errorf("%w: role is required", ErrInvalidInput)
	}
	if u.CreatedAt.IsZero() {
		return fmt.Errorf("%w: created_at is required", ErrInvalidInput)
	}
	return nil
}
