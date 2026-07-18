// Package domain provides shared sentinel errors and typed ID aliases used across
// all Nearby Connect backend microservices. Centralising these values prevents
// duplicate definitions and ensures errors.Is() works across package boundaries.
package domain

import "errors"

// Sentinel errors — use errors.Is(err, domain.ErrXxx) for matching.
var (
	// ErrUnauthorized is returned when credentials are invalid or missing.
	ErrUnauthorized = errors.New("unauthorized")

	// ErrRateLimitExceeded is returned when a sliding-window rate limit is reached.
	ErrRateLimitExceeded = errors.New("rate limit exceeded")

	// ErrReplayDetected is returned when a refresh token is used more than once.
	ErrReplayDetected = errors.New("session compromise detected: refresh token replay")

	// ErrNotFound is returned when a requested entity does not exist.
	ErrNotFound = errors.New("entity not found")

	// ErrConflict is returned when an entity already exists (duplicate key).
	ErrConflict = errors.New("entity already exists")

	// ErrInvalidInput is returned when request payload fails domain validation.
	ErrInvalidInput = errors.New("invalid input")
)

// Typed ID aliases provide compile-time safety against accidental ID field swaps.
type (
	UserID    string
	SessionID string
	RoomID    string
	DeviceID  string
)
