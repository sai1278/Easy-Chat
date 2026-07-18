package domain

import (
	"context"
)

// UserRepository defines PostgreSQL access for user records.
type UserRepository interface {
	Create(ctx context.Context, u *User) error
	GetByID(ctx context.Context, id string) (*User, error)
	GetByDeviceID(ctx context.Context, deviceID string) (*User, error)
	Delete(ctx context.Context, id string) error
}

// SessionRepository defines PostgreSQL access for session records.
type SessionRepository interface {
	Save(ctx context.Context, s *Session) error
	GetByID(ctx context.Context, id string) (*Session, error)
	GetByUserID(ctx context.Context, userID string) ([]*Session, error)
	RevokeSession(ctx context.Context, sessionID string) error
	RevokeAllSessionsForUser(ctx context.Context, userID string) error
}
