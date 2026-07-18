package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	"nearby/backend/services/notification/internal/domain"
)

// RedisQueueRepository implements domain.QueueRepository.
type RedisQueueRepository struct {
	client *redis.Client
	
	// Local thread-safe fallbacks for zero-setup execution and tests
	mu        sync.Mutex
	dupCache  map[string]time.Time
	throttle  map[string][]time.Time
	batches   map[string][]*domain.Notification
	retryList []*domain.Notification
}

// NewRedisQueueRepository creates a new RedisQueueRepository.
func NewRedisQueueRepository(client *redis.Client) *RedisQueueRepository {
	return &RedisQueueRepository{
		client:    client,
		dupCache:  make(map[string]time.Time),
		throttle:  make(map[string][]time.Time),
		batches:   make(map[string][]*domain.Notification),
		retryList: make([]*domain.Notification, 0),
	}
}

// AcquireDeduplicationLock checks if the notification was already processed.
func (r *RedisQueueRepository) AcquireDeduplicationLock(ctx context.Context, notificationID string, ttl time.Duration) (bool, error) {
	if r.client == nil {
		r.mu.Lock()
		defer r.mu.Unlock()
		
		// Clean expired keys
		now := time.Now()
		for k, expiry := range r.dupCache {
			if now.After(expiry) {
				delete(r.dupCache, k)
			}
		}

		if _, exists := r.dupCache[notificationID]; exists {
			return false, nil // Already processed
		}
		r.dupCache[notificationID] = now.Add(ttl)
		return true, nil
	}

	key := fmt.Sprintf("notif:dup:%s", notificationID)
	// Try SETNX (set if not exists)
	success, err := r.client.SetNX(ctx, key, "1", ttl).Result()
	if err != nil {
		return false, err
	}
	return success, nil
}

// RateLimitExceeded implements token bucket throttling.
func (r *RedisQueueRepository) RateLimitExceeded(ctx context.Context, userID string, limit int, window time.Duration) (bool, error) {
	if r.client == nil {
		r.mu.Lock()
		defer r.mu.Unlock()

		now := time.Now()
		timestamps, exists := r.throttle[userID]
		if !exists {
			timestamps = []time.Time{}
		}

		// Filter timestamps inside current rolling window
		var active []time.Time
		cutoff := now.Add(-window)
		for _, t := range timestamps {
			if t.After(cutoff) {
				active = append(active, t)
			}
		}

		if len(active) >= limit {
			return true, nil // Limit reached
		}

		active = append(active, now)
		r.throttle[userID] = active
		return false, nil
	}

	key := fmt.Sprintf("notif:throttle:%s", userID)
	now := time.Now().UnixNano()
	cutoff := time.Now().Add(-window).UnixNano()

	// Use Redis Sorted Set rolling window rate limiting
	pipe := r.client.TxPipeline()
	pipe.ZRemRangeByScore(ctx, key, "-inf", fmt.Sprintf("%d", cutoff))
	pipe.ZAdd(ctx, key, redis.Z{Score: float64(now), Member: fmt.Sprintf("%d", now)})
	pipe.ZCard(ctx, key)
	pipe.Expire(ctx, key, window)

	cmds, err := pipe.Exec(ctx)
	if err != nil {
		return false, err
	}

	card := cmds[2].(*redis.IntCmd).Val()
	if int(card) > limit {
		return true, nil
	}
	return false, nil
}

// QueueRetry writes failing notifications to the retry list.
func (r *RedisQueueRepository) QueueRetry(ctx context.Context, push *domain.Notification, delay time.Duration) error {
	push.Status = "RETRYING"
	if r.client == nil {
		r.mu.Lock()
		defer r.mu.Unlock()
		r.retryList = append(r.retryList, push)
		return nil
	}

	key := "notif:retries"
	data, err := json.Marshal(push)
	if err != nil {
		return err
	}
	_, err = r.client.LPush(ctx, key, data).Result()
	return err
}

// BatchNotification consolidates multiple rapid events into a single push.
func (r *RedisQueueRepository) BatchNotification(ctx context.Context, userID string, push *domain.Notification) (bool, error) {
	if r.client == nil {
		r.mu.Lock()
		defer r.mu.Unlock()

		list := r.batches[userID]
		list = append(list, push)
		r.batches[userID] = list

		// Flush if batch hits 3 notifications
		if len(list) >= 3 {
			r.batches[userID] = nil // Reset batch
			return true, nil
		}
		return false, nil
	}

	key := fmt.Sprintf("notif:batch:%s", userID)
	data, err := json.Marshal(push)
	if err != nil {
		return false, err
	}

	pipe := r.client.TxPipeline()
	pipe.RPush(ctx, key, data)
	pipe.LLen(ctx, key)
	pipe.Expire(ctx, key, 30*time.Second) // Auto-expire after 30s

	cmds, err := pipe.Exec(ctx)
	if err != nil {
		return false, err
	}

	count := cmds[1].(*redis.IntCmd).Val()
	if count >= 3 {
		// Flush batch signal
		r.client.Del(ctx, key)
		return true, nil
	}

	return false, nil
}
