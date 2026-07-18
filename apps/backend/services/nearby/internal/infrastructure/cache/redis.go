package cache

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
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

// UpdateUserLocation adds or updates the user coordinates in the Redis Geo Set with a shadow TTL string.
func (r *RedisGeoRepository) UpdateUserLocation(ctx context.Context, userID string, lat, lon float64, ttl time.Duration) error {
	pipe := r.rdb.Pipeline()

	pipe.GeoAdd(ctx, geoKey, &redis.GeoLocation{
		Name:      userID,
		Latitude:  lat,
		Longitude: lon,
	})

	pipe.Set(ctx, ttlKeyPrefix+userID, "1", ttl)

	_, err := pipe.Exec(ctx)
	return err
}

// RemoveUserLocation deletes the user's location from the Geo Set and shadow TTL string.
func (r *RedisGeoRepository) RemoveUserLocation(ctx context.Context, userID string) error {
	pipe := r.rdb.Pipeline()
	pipe.ZRem(ctx, geoKey, userID)
	pipe.Del(ctx, ttlKeyPrefix+userID)
	_, err := pipe.Exec(ctx)
	return err
}

// FindNearbyUsers queries the Geo Set and cleans up stale users.
func (r *RedisGeoRepository) FindNearbyUsers(ctx context.Context, lat, lon float64, radiusMeters int) ([]string, map[string]float64, error) {
	results, err := r.rdb.GeoSearchLocation(ctx, geoKey, &redis.GeoSearchLocationQuery{
		GeoSearchQuery: redis.GeoSearchQuery{
			Longitude:  lon,
			Latitude:   lat,
			Radius:     float64(radiusMeters),
			RadiusUnit: "m",
			Sort:       "ASC",
		},
		WithDist: true,
	}).Result()

	if err != nil {
		return nil, nil, err
	}

	if len(results) == 0 {
		return []string{}, make(map[string]float64), nil
	}

	// Pipelined exists checks to avoid N+1 query overhead
	pipe := r.rdb.Pipeline()
	existsCmds := make([]*redis.IntCmd, len(results))
	for i, loc := range results {
		existsCmds[i] = pipe.Exists(ctx, ttlKeyPrefix+loc.Name)
	}
	_, _ = pipe.Exec(ctx)

	userIDs := make([]string, 0, len(results))
	distances := make(map[string]float64)
	var expiredUserIDs []string

	for i, loc := range results {
		exists, err := existsCmds[i].Result()
		if err != nil || exists == 0 {
			expiredUserIDs = append(expiredUserIDs, loc.Name)
			continue
		}

		userIDs = append(userIDs, loc.Name)
		distances[loc.Name] = loc.Dist
	}

	// Clean up expired user keys from Geo Set asynchronously
	if len(expiredUserIDs) > 0 {
		go func(ids []string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = r.rdb.ZRem(bgCtx, geoKey, ids).Err()
		}(expiredUserIDs)
	}

	return userIDs, distances, nil
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
