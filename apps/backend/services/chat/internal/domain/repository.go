package domain

import (
	"context"
	"time"
)

// ChatRepository defines PostgreSQL database access methods.
type ChatRepository interface {
	SaveMessage(ctx context.Context, msg *Message) error
	SaveReceipt(ctx context.Context, receipt *ReadReceipt) error
	GetRoomMessagesSince(ctx context.Context, roomID string, since time.Time) ([]*Message, error)
	GetRoomsMessagesSince(ctx context.Context, roomIDs []string, since time.Time, limit, offset int) ([]*Message, error)
	GetActiveRoomsForUser(ctx context.Context, userID string) ([]string, error)
}

// RoomRepository defines lookup of chat room membership.
// Used by the Kafka consumer in the WebSocket transport to route events
// without issuing raw SQL from the transport layer (HIGH-06 fix).
type RoomRepository interface {
	// GetMembers returns the user IDs of all participants in the given room.
	GetMembers(ctx context.Context, roomID string) ([]string, error)
	// GetOrCreateRoom fetches or creates a mutually unique active chat room for the two users.
	GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error)
}

// CacheRepository defines Redis cache operations, idempotency keys, and pub/sub.
type CacheRepository interface {
	SetIdempotencyKey(ctx context.Context, key string, ttl time.Duration) (bool, error)
	PublishTyping(ctx context.Context, indicator *TypingIndicator) error
	SubscribeRoomTyping(ctx context.Context, roomID string) (<-chan *TypingIndicator, func() error, error)
	SetUserOnline(ctx context.Context, userID string, isOnline bool) error
	IsUserOnline(ctx context.Context, userID string) (bool, error)
}

// EventPipeline defines Kafka message delivery pub/sub.
type EventPipeline interface {
	PublishChatEvent(ctx context.Context, event *EventPacket) error
	ConsumeChatEvents(ctx context.Context) (<-chan *EventPacket, error)
	Close() error
}
