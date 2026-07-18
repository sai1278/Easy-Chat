package application

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"nearby/backend/services/nearby/internal/domain"
)

var (
	// ErrRateLimitExceeded is returned when the user exceeds the anti-spam rate limits.
	ErrRateLimitExceeded = errors.New("rate limit exceeded")
)

// NearbyUsecase implements the nearby user proximity search and throttling use cases.
type NearbyUsecase struct {
	userRepo domain.UserRepository
	geoRepo  domain.GeoRepository
}

// NewNearbyUsecase creates a new NearbyUsecase.
func NewNearbyUsecase(userRepo domain.UserRepository, geoRepo domain.GeoRepository) *NearbyUsecase {
	return &NearbyUsecase{
		userRepo: userRepo,
		geoRepo:  geoRepo,
	}
}

// FindNearby handles the proximity search, updating requester location, throttling, block filtering, and status checks.
func (u *NearbyUsecase) FindNearby(
	ctx context.Context,
	userID string,
	lat, lon float64,
	radiusMeters int,
	throttleLimit int,
	throttleWindow time.Duration,
) ([]*domain.NearbyUser, error) {
	// 1. Anti-spam throttling check in Redis
	allowed, err := u.geoRepo.CheckThrottling(ctx, userID, throttleLimit, throttleWindow)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, ErrRateLimitExceeded
	}

	// 2. Self-publishing: Fetch requester's own status/visibility to update location index
	ownMetadata, err := u.userRepo.GetActiveUsersMetadata(ctx, []string{userID})
	if err == nil {
		if meta, exists := ownMetadata[userID]; exists && meta.Status == "ACTIVE" && meta.IsVisible {
			// Requester is active and visible; publish/update their location in Redis Geo Set
			_ = u.geoRepo.UpdateUserLocation(ctx, userID, lat, lon, 60*time.Second)
		}
	}

	// 3. Query Redis Geo Index for nearby user IDs within radius
	nearbyIDs, distances, err := u.geoRepo.FindNearbyUsers(ctx, lat, lon, radiusMeters)
	if err != nil {
		return nil, err
	}

	// Filter out the requester ID itself from candidate list
	var candidates []string
	for _, id := range nearbyIDs {
		if id != userID {
			candidates = append(candidates, id)
		}
	}

	if len(candidates) == 0 {
		return []*domain.NearbyUser{}, nil
	}

	// 4. Query blocked relationships from Postgres (both blocker and blocked)
	blockedMap, err := u.userRepo.GetBlockFilter(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Filter out blocked users
	var nonBlockedCandidates []string
	for _, id := range candidates {
		if !blockedMap[id] {
			nonBlockedCandidates = append(nonBlockedCandidates, id)
		}
	}

	if len(nonBlockedCandidates) == 0 {
		return []*domain.NearbyUser{}, nil
	}

	// 5. Query Postgres for profiles, status, and visibility (filters ACTIVE & is_visible = TRUE)
	metadataMap, err := u.userRepo.GetActiveUsersMetadata(ctx, nonBlockedCandidates)
	if err != nil {
		return nil, err
	}
	slog.Info("FindNearby debug details", "candidates", candidates, "blockedMap", blockedMap, "nonBlockedCandidates", nonBlockedCandidates, "metadataMap", metadataMap)

	// 6. Build, bucket, and sort results (preserving distance ascending order from Redis)
	var results []*domain.NearbyUser
	for _, id := range nonBlockedCandidates {
		meta, exists := metadataMap[id]
		if !exists {
			// Excluded because user is inactive, invisible, or missing profile metadata
			continue
		}

		dist := distances[id]
		// Skip if distance is somehow greater than requested radius
		if dist > float64(radiusMeters) {
			continue
		}

		var bucket string
		if dist <= 100 {
			bucket = "within 100m"
		} else if dist <= 200 {
			bucket = "within 200m"
		} else {
			bucket = "beyond 200m"
		}

		results = append(results, &domain.NearbyUser{
			UserID:         meta.UserID,
			Pseudonym:      meta.Pseudonym,
			AvatarID:       meta.AvatarID,
			DistanceMeters: dist,
			DistanceBucket: bucket,
		})
	}

	return results, nil
}
