package application

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
	"nearby/backend/shared/geo"
)

const (
	redisLocationDataPrefix = "nearby:location:data:"
	redisLocationTTLPrefix  = "nearby:location:ttl:"
	redisLocationAccPrefix  = "nearby:location:acc:"
)

// ProximityValidator enforces server-authoritative geographic proximity rules.
type ProximityValidator struct {
	rdb *redis.Client
	db  *sql.DB
}

// NewProximityValidator creates a new ProximityValidator instance.
func NewProximityValidator(rdb *redis.Client, db *sql.DB) *ProximityValidator {
	return &ProximityValidator{
		rdb: rdb,
		db:  db,
	}
}

// GetUserLocation retrieves authoritative location data from Redis, falling back to Postgres.
func (pv *ProximityValidator) GetUserLocation(ctx context.Context, userID string) (*geo.LocationData, error) {
	if userID == "" {
		return nil, errors.New("empty user_id")
	}

	// 1. Try Redis cached location data JSON
	if pv.rdb != nil {
		val, err := pv.rdb.Get(ctx, redisLocationDataPrefix+userID).Result()
		if err == nil && val != "" {
			var loc geo.LocationData
			if err := json.Unmarshal([]byte(val), &loc); err == nil {
				return &loc, nil
			}
		}

		// Check if GeoSet has coordinates if data key was missing
		pos, err := pv.rdb.GeoPos(ctx, "nearby:locations", userID).Result()
		if err == nil && len(pos) > 0 && pos[0] != nil {
			accStr, _ := pv.rdb.Get(ctx, redisLocationAccPrefix+userID).Result()
			var acc float64 = 10.0
			if accStr != "" {
				_, _ = fmt.Sscanf(accStr, "%f", &acc)
			}
			return &geo.LocationData{
				UserID:         userID,
				Latitude:       pos[0].Latitude,
				Longitude:      pos[0].Longitude,
				AccuracyMeters: acc,
				UpdatedAt:      time.Now().UTC(),
			}, nil
		}
	}

	// 2. Fallback to PostgreSQL user_locations table
	if pv.db != nil {
		query := `
			SELECT latitude, longitude, accuracy_meters, updated_at
			FROM user_locations
			WHERE user_id = $1`
		var loc geo.LocationData
		loc.UserID = userID
		err := pv.db.QueryRowContext(ctx, query, userID).Scan(
			&loc.Latitude,
			&loc.Longitude,
			&loc.AccuracyMeters,
			&loc.UpdatedAt,
		)
		if err == nil {
			return &loc, nil
		}
	}

	return nil, errors.New("location not found")
}

// Validate checks physical proximity between two users.
func (pv *ProximityValidator) Validate(ctx context.Context, userA, userB string, requestID string) geo.ProximityResult {
	now := time.Now().UTC()

	locA, errA := pv.GetUserLocation(ctx, userA)
	locB, errB := pv.GetUserLocation(ctx, userB)

	if errA != nil || errB != nil || locA == nil || locB == nil {
		res := geo.ProximityResult{
			Status:                geo.ProximityLocationUnavailable,
			Allowed:               false,
			MaxChatDistanceMeters: geo.MaxChatDistanceMeters,
			Message:               "Location unavailable or outdated for one or both users.",
		}
		slog.Warn("PROXIMITY_CHECK",
			"request_id", requestID,
			"user_a", userA,
			"user_b", userB,
			"distance_meters", -1.0,
			"max_distance_meters", geo.MaxChatDistanceMeters,
			"result", "BLOCK",
			"reason", string(res.Status),
		)
		return res
	}

	res := geo.EvaluateProximity(locA, locB, now)

	resultStr := "BLOCK"
	if res.Allowed {
		resultStr = "ALLOW"
	}

	// Structured production log without logging sensitive exact coordinates
	slog.Info("PROXIMITY_CHECK",
		"request_id", requestID,
		"user_a", userA,
		"user_b", userB,
		"distance_meters", res.DistanceMeters,
		"max_distance_meters", geo.MaxChatDistanceMeters,
		"result", resultStr,
		"reason", string(res.Status),
	)

	return res
}
