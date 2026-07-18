package cache

import (
	"context"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"
	"nearby/backend/services/chat/internal/domain"
)

// RedisCacheRepository implements domain.CacheRepository.
type RedisCacheRepository struct {
	rdb *redis.Client
}

// NewRedisCacheRepository creates a new RedisCacheRepository.
func NewRedisCacheRepository(rdb *redis.Client) *RedisCacheRepository {
	return &RedisCacheRepository{rdb: rdb}
}

// SetIdempotencyKey checks and sets an idempotency key. Returns true if the key did not exist.
func (r *RedisCacheRepository) SetIdempotencyKey(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	return r.rdb.SetNX(ctx, "chat:idemp:"+key, "1", ttl).Result()
}

// PublishTyping publishes a typing event to Redis Pub/Sub.
func (r *RedisCacheRepository) PublishTyping(ctx context.Context, indicator *domain.TypingIndicator) error {
	payload, err := json.Marshal(indicator)
	if err != nil {
		return err
	}
	return r.rdb.Publish(ctx, "chat:typing:room:"+indicator.RoomID, payload).Err()
}

// SubscribeRoomTyping subscribes to a room's typing events and returns a channel and cleanup function.
func (r *RedisCacheRepository) SubscribeRoomTyping(ctx context.Context, roomID string) (<-chan *domain.TypingIndicator, func() error, error) {
	pubsub := r.rdb.Subscribe(ctx, "chat:typing:room:"+roomID)
	ch := make(chan *domain.TypingIndicator, 100)

	go func() {
		defer close(ch)
		for msg := range pubsub.Channel() {
			var indicator domain.TypingIndicator
			if err := json.Unmarshal([]byte(msg.Payload), &indicator); err == nil {
				ch <- &indicator
			}
		}
	}()

	cleanup := func() error {
		return pubsub.Close()
	}

	return ch, cleanup, nil
}

// SetUserOnline sets the user's online cache status.
func (r *RedisCacheRepository) SetUserOnline(ctx context.Context, userID string, isOnline bool) error {
	if isOnline {
		return r.rdb.Set(ctx, "chat:online:"+userID, "1", 24*time.Hour).Err()
	}
	return r.rdb.Del(ctx, "chat:online:"+userID).Err()
}

// IsUserOnline checks whether the user is online.
func (r *RedisCacheRepository) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	res, err := r.rdb.Exists(ctx, "chat:online:"+userID).Result()
	return res > 0, err
}
