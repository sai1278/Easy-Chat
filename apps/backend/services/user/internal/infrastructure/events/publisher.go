package events

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// ProfileUpdatedEvent represents the enterprise domain event published when a profile changes.
type ProfileUpdatedEvent struct {
	Type        string    `json:"type"`
	UserID      string    `json:"user_id"`
	Username    string    `json:"username,omitempty"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	Bio         string    `json:"bio"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// EventPublisher defines the contract for domain event publishing.
type EventPublisher interface {
	PublishProfileUpdated(ctx context.Context, event *ProfileUpdatedEvent) error
}

// RedisEventPublisher implements EventPublisher using Redis Pub/Sub.
type RedisEventPublisher struct {
	rdb *redis.Client
}

// NewRedisEventPublisher creates a new RedisEventPublisher.
func NewRedisEventPublisher(rdb *redis.Client) *RedisEventPublisher {
	return &RedisEventPublisher{rdb: rdb}
}

// PublishProfileUpdated publishes a ProfileUpdatedEvent to the "events:profile_updated" Redis Pub/Sub channel.
func (p *RedisEventPublisher) PublishProfileUpdated(ctx context.Context, event *ProfileUpdatedEvent) error {
	if event.Type == "" {
		event.Type = "PROFILE_UPDATED"
	}
	if event.UpdatedAt.IsZero() {
		event.UpdatedAt = time.Now().UTC()
	}

	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal ProfileUpdatedEvent: %w", err)
	}

	return p.rdb.Publish(ctx, "events:profile_updated", payload).Err()
}
