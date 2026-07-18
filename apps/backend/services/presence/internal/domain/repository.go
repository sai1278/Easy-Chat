package domain

import (
	"context"
	"time"
)

type PresenceRepository interface {
	// Device operations
	UpdateDevicePresence(ctx context.Context, userID, deviceID string, state PresenceState, h3Index string, ttl time.Duration) error
	GetDevicePresences(ctx context.Context, userID string) ([]*DevicePresence, error)
	RemoveDevicePresence(ctx context.Context, userID, deviceID string) error

	// Spatial location operations (Geohash sharding)
	UpdateGeohashIndex(ctx context.Context, userID string, h3Index string, ttl time.Duration) error
	RemoveFromGeohashIndex(ctx context.Context, userID string, h3Index string) error
}
