package application

import (
	"context"
	"time"

	"nearby/backend/services/presence/internal/domain"
)

type PresenceUsecase struct {
	presenceRepo domain.PresenceRepository
}

func NewPresenceUsecase(repo domain.PresenceRepository) *PresenceUsecase {
	return &PresenceUsecase{presenceRepo: repo}
}

// Heartbeat refreshes device session TTL and updates H3 geohash indices.
func (u *PresenceUsecase) Heartbeat(ctx context.Context, userID, deviceID string, state domain.PresenceState, h3Index string) error {
	// Set TTL to 45 seconds to cover the 30-second heartbeat cycle window (Decision 1)
	ttl := 45 * time.Second

	// 1. Update the local device presence session in Redis cache
	if err := u.presenceRepo.UpdateDevicePresence(ctx, userID, deviceID, state, h3Index, ttl); err != nil {
		return err
	}

	// 2. Adjust visibility geohashing indexing based on presence state (Decision 3)
	if state == domain.StateInvisible || state == domain.StateOffline {
		return u.presenceRepo.RemoveFromGeohashIndex(ctx, userID, h3Index)
	}

	return u.presenceRepo.UpdateGeohashIndex(ctx, userID, h3Index, ttl)
}

// DisconnectDevice handles sudden connection drops or clean logouts.
func (u *PresenceUsecase) DisconnectDevice(ctx context.Context, userID, deviceID string) error {
	// Immediate cleanup of device key to speed up offline status resolution
	if err := u.presenceRepo.RemoveDevicePresence(ctx, userID, deviceID); err != nil {
		return err
	}

	// Get remaining devices to recalculate aggregated presence state (Decision 2)
	devices, err := u.presenceRepo.GetDevicePresences(ctx, userID)
	if err != nil {
		return err
	}

	// If no devices remain active, remove from geohashing search index completely
	if len(devices) == 0 {
		// Mock query to remove from H3 indices
		return u.presenceRepo.RemoveFromGeohashIndex(ctx, userID, "")
	}

	return nil
}
