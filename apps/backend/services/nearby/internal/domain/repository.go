package domain

import (
	"context"
	"time"

	"nearby/backend/shared/geo"
)

// UserRepository defines metadata, block, and persistent location operations on Postgres.
type UserRepository interface {
	GetActiveUsersMetadata(ctx context.Context, userIDs []string) (map[string]*UserMetadata, error)
	GetBlockFilter(ctx context.Context, userID string) (map[string]bool, error)
	UpsertUserLocation(ctx context.Context, userID string, lat, lon float64, accuracy float64, updatedAt ...time.Time) error
	GetUserLocation(ctx context.Context, userID string) (*geo.LocationData, error)
}

// GeoRepository defines geospatial, location cache, and throttling operations on Redis.
type GeoRepository interface {
	UpdateUserLocation(ctx context.Context, userID string, lat, lon float64, accuracy *float64, ttl time.Duration, updatedAt ...time.Time) error
	RemoveUserLocation(ctx context.Context, userID string) error
	FindNearbyUsers(ctx context.Context, lat, lon float64, radiusMeters int) ([]string, map[string]float64, map[string]float64, error)
	GetUserLocation(ctx context.Context, userID string) (*geo.LocationData, error)
	CheckThrottling(ctx context.Context, userID string, limit int, window time.Duration) (bool, error)
}
