// Package cache implements the auth service's Redis-backed rate limiter and token
// blacklist using a real go-redis/v9 client. This replaces the placeholder stubs
// that previously caused all rate limiting and blacklisting to be bypassed.
package cache

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	prefixBlacklist  = "auth:bl:"
	prefixRateWindow = "auth:rate:"
)

// RedisCache provides session revocation and sliding-window rate limiting using
// a real Redis connection. It is safe for concurrent use.
type RedisCache struct {
	rdb *redis.Client
}

// NewRedisCache initialises the Redis client and verifies connectivity with PING.
func NewRedisCache(addr, password string, db int) (*RedisCache, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:         addr,
		Password:     password,
		DB:           db,
		DialTimeout:  3 * time.Second,
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
		PoolSize:     10,
		MinIdleConns: 2,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}
	return &RedisCache{rdb: rdb}, nil
}

// BlacklistToken writes the session ID into the Redis blacklist with the given TTL.
// After this call, IsTokenBlacklisted returns true for the same sessionID.
func (c *RedisCache) BlacklistToken(ctx context.Context, sessionID string, expiration time.Duration) error {
	key := prefixBlacklist + sessionID
	return c.rdb.Set(ctx, key, "1", expiration).Err()
}

// IsTokenBlacklisted returns true when the session ID is present in the blacklist.
// Returns false (and a nil error) when the key is absent — indicating the token is valid.
func (c *RedisCache) IsTokenBlacklisted(ctx context.Context, sessionID string) (bool, error) {
	key := prefixBlacklist + sessionID
	res, err := c.rdb.Exists(ctx, key).Result()
	if err != nil {
		return false, fmt.Errorf("redis exists: %w", err)
	}
	return res > 0, nil
}

// AssertRateLimit implements a sliding-window rate limiter using a Redis sorted set.
// It records the current request timestamp, removes stale entries outside the window,
// and rejects requests when the count exceeds maxLimit.
//
// Returns (true, nil) when the request is allowed.
// Returns (false, nil) when the rate limit is exceeded.
func (c *RedisCache) AssertRateLimit(ctx context.Context, rateKey string, maxLimit int, window time.Duration) (bool, error) {
	key := prefixRateWindow + rateKey
	now := time.Now().UnixNano()
	windowStart := now - window.Nanoseconds()

	pipe := c.rdb.Pipeline()
	// Remove entries older than the window.
	pipe.ZRemRangeByScore(ctx, key, "0", fmt.Sprintf("%d", windowStart))
	// Count current entries.
	countCmd := pipe.ZCard(ctx, key)
	// Add current request.
	pipe.ZAdd(ctx, key, redis.Z{Score: float64(now), Member: fmt.Sprintf("%d", now)})
	// Refresh TTL.
	pipe.Expire(ctx, key, window)

	if _, err := pipe.Exec(ctx); err != nil {
		return false, fmt.Errorf("redis rate limit pipeline: %w", err)
	}

	count := countCmd.Val()
	return int(count) < maxLimit, nil
}

// Close gracefully shuts down the Redis connection pool.
func (c *RedisCache) Close() error {
	return c.rdb.Close()
}
