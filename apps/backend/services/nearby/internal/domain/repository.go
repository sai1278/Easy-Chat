package domain

import (
	"context"
	"time"
)

// UserRepository defines metadata and block operations on Postgres.
type UserRepository interface {
	GetActiveUsersMetadata(ctx context.Context, userIDs []string) (map[string]*UserMetadata, error)
	GetBlockFilter(ctx context.Context, userID string) (map[string]bool, error)
}

// GeoRepository defines geospatial and throttling operations on Redis.
type GeoRepository interface {
	UpdateUserLocation(ctx context.Context, userID string, lat, lon float64, ttl time.Duration) error
	RemoveUserLocation(ctx context.Context, userID string) error
	FindNearbyUsers(ctx context.Context, lat, lon float64, radiusMeters int) ([]string, map[string]float64, error)
	CheckThrottling(ctx context.Context, userID string, limit int, window time.Duration) (bool, error)
}
