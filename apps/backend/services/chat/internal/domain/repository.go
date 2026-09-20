package domain

import (
	"context"
	"time"
)

// ChatRepository defines PostgreSQL database access methods.
type ChatRepository interface {
	SaveMessage(ctx context.Context, msg *Message) error
	SaveReceipt(ctx context.Context, receipt *ReadReceipt) error
	GetMessageByID(ctx context.Context, messageID, roomID string) (*Message, error)
	DeleteMessageForEveryone(ctx context.Context, messageID, roomID, senderID string) error
	GetDeletedMessagesSince(ctx context.Context, roomIDs []string, since time.Time) ([]string, error)
	GetRoomMessagesSince(ctx context.Context, roomID string, since time.Time) ([]*Message, error)
	GetRoomsMessagesSince(ctx context.Context, roomIDs []string, since time.Time, limit, offset int) ([]*Message, error)
	GetActiveRoomsForUser(ctx context.Context, userID string) ([]string, error)
	SaveCryptoIdentity(ctx context.Context, identity *UserCryptoIdentity) error
	GetCryptoIdentity(ctx context.Context, userID string) (*UserCryptoIdentity, error)
}

// RoomRepository defines lookup of chat room membership and status.
type RoomRepository interface {
	GetMembers(ctx context.Context, roomID string) ([]string, error)
	GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error)
	IsRoomActive(ctx context.Context, roomID string) (bool, error)
}

// RequestRepository defines PostgreSQL database methods for chat request lifecycle.
type RequestRepository interface {
	CreateRequest(ctx context.Context, senderID, recipientID string) (*ChatRequest, error)
	GetPendingRequestsForUser(ctx context.Context, recipientID string) ([]*ChatRequest, error)
	GetRequestByID(ctx context.Context, requestID string) (*ChatRequest, error)
	GetRequestBetweenUsers(ctx context.Context, userA, userB string) (*ChatRequest, error)
	AcceptRequest(ctx context.Context, requestID, recipientID string) (*ChatRequest, error)
	DenyRequest(ctx context.Context, requestID, recipientID string) (*ChatRequest, error)
	IsRoomActiveAndAccepted(ctx context.Context, roomID string) (bool, error)
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
