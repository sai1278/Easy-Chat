package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/redis/go-redis/v9"
	"nearby/backend/shared/geo"
)

// RedisGeoRepository implements domain.GeoRepository.
type RedisGeoRepository struct {
	rdb *redis.Client
}

// NewRedisGeoRepository creates a new RedisGeoRepository.
func NewRedisGeoRepository(rdb *redis.Client) *RedisGeoRepository {
	return &RedisGeoRepository{rdb: rdb}
}

const geoKey = "nearby:locations"
const ttlKeyPrefix = "nearby:location:ttl:"
const accuracyKeyPrefix = "nearby:location:acc:"
const dataKeyPrefix = "nearby:location:data:"

// UpdateUserLocation adds or updates the user coordinates in the Redis Geo Set with shadow TTL, accuracy, and structured location data.
func (r *RedisGeoRepository) UpdateUserLocation(ctx context.Context, userID string, lat, lon float64, accuracy *float64, ttl time.Duration, updatedAt ...time.Time) error {
	pipe := r.rdb.Pipeline()

	updateTime := time.Now().UTC()
	if len(updatedAt) > 0 && !updatedAt[0].IsZero() {
		updateTime = updatedAt[0].UTC()
	}

	pipe.GeoAdd(ctx, geoKey, &redis.GeoLocation{
		Name:      userID,
		Latitude:  lat,
		Longitude: lon,
	})

	pipe.Set(ctx, ttlKeyPrefix+userID, "1", ttl)
	var accVal float64 = 10.0
	if accuracy != nil && *accuracy > 0 {
		accVal = *accuracy
		pipe.Set(ctx, accuracyKeyPrefix+userID, fmt.Sprintf("%.2f", accVal), ttl)
	}

	locJSON, _ := json.Marshal(&geo.LocationData{
		UserID:         userID,
		Latitude:       lat,
		Longitude:      lon,
		AccuracyMeters: accVal,
		UpdatedAt:      updateTime,
	})
	pipe.Set(ctx, dataKeyPrefix+userID, string(locJSON), 120*time.Second)

	_, err := pipe.Exec(ctx)
	return err
}

// RemoveUserLocation deletes the user's location from the Geo Set, shadow TTL string, and location data.
func (r *RedisGeoRepository) RemoveUserLocation(ctx context.Context, userID string) error {
	pipe := r.rdb.Pipeline()
	pipe.ZRem(ctx, geoKey, userID)
	pipe.Del(ctx, ttlKeyPrefix+userID)
	pipe.Del(ctx, accuracyKeyPrefix+userID)
	pipe.Del(ctx, dataKeyPrefix+userID)
	_, err := pipe.Exec(ctx)
	return err
}

// GetUserLocation retrieves the structured location data from Redis cache.
func (r *RedisGeoRepository) GetUserLocation(ctx context.Context, userID string) (*geo.LocationData, error) {
	val, err := r.rdb.Get(ctx, dataKeyPrefix+userID).Result()
	if err == nil && val != "" {
		var loc geo.LocationData
		if err := json.Unmarshal([]byte(val), &loc); err == nil {
			return &loc, nil
		}
	}

	pos, err := r.rdb.GeoPos(ctx, geoKey, userID).Result()
	if err == nil && len(pos) > 0 && pos[0] != nil {
		accStr, _ := r.rdb.Get(ctx, accuracyKeyPrefix+userID).Result()
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

	return nil, fmt.Errorf("location not found in redis for user: %s", userID)
}

// FindNearbyUsers queries the Geo Set and cleans up stale users.
func (r *RedisGeoRepository) FindNearbyUsers(ctx context.Context, lat, lon float64, radiusMeters int) ([]string, map[string]float64, map[string]float64, error) {
	results, err := r.rdb.GeoSearchLocation(ctx, geoKey, &redis.GeoSearchLocationQuery{
		GeoSearchQuery: redis.GeoSearchQuery{
			Longitude:  lon,
			Latitude:   lat,
			Radius:     float64(radiusMeters),
			RadiusUnit: "m",
			Sort:       "ASC",
		},
		WithDist:  true,
		WithCoord: true,
	}).Result()

	if err != nil {
		return nil, nil, nil, err
	}

	if len(results) == 0 {
		return []string{}, make(map[string]float64), make(map[string]float64), nil
	}

	// Pipelined exists and accuracy checks to avoid N+1 query overhead
	pipe := r.rdb.Pipeline()
	existsCmds := make([]*redis.IntCmd, len(results))
	accCmds := make([]*redis.StringCmd, len(results))
	for i, loc := range results {
		existsCmds[i] = pipe.Exists(ctx, ttlKeyPrefix+loc.Name)
		accCmds[i] = pipe.Get(ctx, accuracyKeyPrefix+loc.Name)
	}
	_, _ = pipe.Exec(ctx)

	userIDs := make([]string, 0, len(results))
	distances := make(map[string]float64)
	accuracies := make(map[string]float64)
	var expiredUserIDs []string

	for i, loc := range results {
		exists, err := existsCmds[i].Result()
		if err != nil || exists == 0 {
			expiredUserIDs = append(expiredUserIDs, loc.Name)
			continue
		}

		userIDs = append(userIDs, loc.Name)
		dist := loc.Dist
		if loc.Latitude != 0.0 || loc.Longitude != 0.0 {
			dist = geo.HaversineDistance(lat, lon, loc.Latitude, loc.Longitude)
			dist = math.Round(dist*100.0) / 100.0
		}
		distances[loc.Name] = dist

		if accStr, accErr := accCmds[i].Result(); accErr == nil {
			var accVal float64
			if n, _ := fmt.Sscanf(accStr, "%f", &accVal); n == 1 && accVal > 0 {
				accuracies[loc.Name] = accVal
			}
		}
	}

	// Clean up expired user keys from Geo Set asynchronously
	if len(expiredUserIDs) > 0 {
		go func(ids []string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = r.rdb.ZRem(bgCtx, geoKey, ids).Err()
			delPipe := r.rdb.Pipeline()
			for _, id := range ids {
				delPipe.Del(bgCtx, accuracyKeyPrefix+id)
			}
			_, _ = delPipe.Exec(bgCtx)
		}(expiredUserIDs)
	}

	return userIDs, distances, accuracies, nil
}

// CheckThrottling checks if a user is within request limit using atomic Lua script sliding window.
func (r *RedisGeoRepository) CheckThrottling(ctx context.Context, userID string, limit int, window time.Duration) (bool, error) {
	key := fmt.Sprintf("nearby:throttle:%s", userID)
	now := time.Now()
	nowMs := now.UnixNano() / int64(time.Millisecond)
	clearBefore := now.Add(-window).UnixNano() / int64(time.Millisecond)

	script := `
		local key = KEYS[1]
		local now = tonumber(ARGV[1])
		local clearBefore = tonumber(ARGV[2])
		local limit = tonumber(ARGV[3])
		local windowMs = tonumber(ARGV[4])

		redis.call('zremrangebyscore', key, '-inf', clearBefore)
		local count = redis.call('zcard', key)

		if count < limit then
			redis.call('zadd', key, now, now)
			redis.call('pexpire', key, windowMs)
			return 1
		else
			return 0
		end
	`

	allowed, err := r.rdb.Eval(ctx, script, []string{key}, nowMs, clearBefore, limit, window.Milliseconds()).Int()
	if err != nil {
		return false, err
	}

	return allowed == 1, nil
}
