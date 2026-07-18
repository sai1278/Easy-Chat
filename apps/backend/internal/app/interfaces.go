package app

import (
	"context"
	"time"
)

// User represents the domain model of an anonymous profile.
type User struct {
	ID        string    `json:"id"`
	Pseudonym string    `json:"pseudonym"`
	AvatarID  int       `json:"avatar_id"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Session represents a verified JWT auth session.
type Session struct {
	ID           string    `json:"id"`
	UserID       string    `json:"user_id"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
	CreatedAt    time.Time `json:"created_at"`
}

// ChatRequest represents a proximity request handshake.
type ChatRequest struct {
	ID           string    `json:"request_id"`
	SenderID     string    `json:"sender_id"`
	TargetUserID string    `json:"target_user_id"`
	Status       string    `json:"status"`
	ExpiresAt    time.Time `json:"expires_at"`
}

// =====================================================
// REPOSITORY LAYER INTERFACES
// =====================================================

type UserRepository interface {
	Create(ctx context.Context, u *User) error
	GetByID(ctx context.Context, id string) (*User, error)
	Update(ctx context.Context, u *User) error
	Delete(ctx context.Context, id string) error
}

type SessionRepository interface {
	Save(ctx context.Context, s *Session) error
	GetByHash(ctx context.Context, tokenHash string) (*Session, error)
	Revoke(ctx context.Context, id string) error
}

type ChatRepository interface {
	SaveRequest(ctx context.Context, r *ChatRequest) error
	GetRequestByID(ctx context.Context, id string) (*ChatRequest, error)
	UpdateRequest(ctx context.Context, r *ChatRequest) error
}

// =====================================================
// SERVICE LAYER INTERFACES
// =====================================================

type AuthService interface {
	Onboard(ctx context.Context) (*User, string, string, error)
	RefreshToken(ctx context.Context, oldRefreshToken string) (string, string, error)
}

type ProximityService interface {
	ToggleVisibility(ctx context.Context, userID string, h3Index string, radius int, isVisible bool) error
	GetNearby(ctx context.Context, userID string, radius int) ([]User, error)
}
