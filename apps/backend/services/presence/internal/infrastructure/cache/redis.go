package cache

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"nearby/backend/services/presence/internal/domain"
)

type RedisPresenceRepository struct {
	rdb *redis.Client
}

func NewRedisPresenceRepository(rdb *redis.Client) *RedisPresenceRepository {
	return &RedisPresenceRepository{rdb: rdb}
}

func (r *RedisPresenceRepository) UpdateDevicePresence(ctx context.Context, userID, deviceID string, state domain.PresenceState, h3Index string, ttl time.Duration) error {
	key := fmt.Sprintf("nearby:presence:device:%s:%s", userID, deviceID)
	val := fmt.Sprintf("%s:%s", h3Index, state)
	return r.rdb.Set(ctx, key, val, ttl).Err()
}

func (r *RedisPresenceRepository) GetDevicePresences(ctx context.Context, userID string) ([]*domain.DevicePresence, error) {
	pattern := fmt.Sprintf("nearby:presence:device:%s:*", userID)
	keys, err := r.rdb.Keys(ctx, pattern).Result()
	if err != nil {
		return nil, fmt.Errorf("keys lookup: %w", err)
	}

	var devices []*domain.DevicePresence
	for _, key := range keys {
		val, err := r.rdb.Get(ctx, key).Result()
		if err != nil {
			if err == redis.Nil {
				continue
			}
			return nil, fmt.Errorf("get device: %w", err)
		}

		parts := strings.SplitN(val, ":", 2)
		if len(parts) != 2 {
			continue
		}

		partsKey := strings.Split(key, ":")
		devID := partsKey[len(partsKey)-1]

		devices = append(devices, &domain.DevicePresence{
			DeviceID:  devID,
			H3Index:   parts[0],
			State:     domain.PresenceState(parts[1]),
			UpdatedAt: time.Now(),
		})
	}
	return devices, nil
}

func (r *RedisPresenceRepository) RemoveDevicePresence(ctx context.Context, userID, deviceID string) error {
	key := fmt.Sprintf("nearby:presence:device:%s:%s", userID, deviceID)
	return r.rdb.Del(ctx, key).Err()
}

func (r *RedisPresenceRepository) UpdateGeohashIndex(ctx context.Context, userID string, h3Index string, ttl time.Duration) error {
	key := "nearby:geo:shard:851f"
	err := r.rdb.ZAdd(ctx, key, redis.Z{
		Score:  0,
		Member: userID,
	}).Err()
	if err != nil {
		return err
	}
	return r.rdb.Expire(ctx, key, ttl).Err()
}

func (r *RedisPresenceRepository) RemoveFromGeohashIndex(ctx context.Context, userID string, h3Index string) error {
	key := "nearby:geo:shard:851f"
	return r.rdb.ZRem(ctx, key, userID).Err()
}
