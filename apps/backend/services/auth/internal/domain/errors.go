package domain

import "errors"

// Sentinel errors for the auth service domain.
var (
	ErrUnauthorized      = errors.New("unauthorized")
	ErrRateLimitExceeded = errors.New("rate limit exceeded")
	ErrReplayDetected    = errors.New("session compromise detected: refresh token replay")
	ErrNotFound          = errors.New("entity not found")
	ErrConflict          = errors.New("entity already exists")
	ErrInvalidInput      = errors.New("invalid input")
)
