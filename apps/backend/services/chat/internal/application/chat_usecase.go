package application

import (
	"context"
	"time"

	"nearby/backend/services/chat/internal/domain"
)

// ChatUsecase orchestrates the chat messaging, receipt processing, typing indicators, and history recovery.
type ChatUsecase struct {
	chatRepo  domain.ChatRepository
	roomRepo  domain.RoomRepository
	cacheRepo domain.CacheRepository
	pipeline  domain.EventPipeline
}

// NewChatUsecase creates a new ChatUsecase.
func NewChatUsecase(
	chatRepo domain.ChatRepository,
	roomRepo domain.RoomRepository,
	cacheRepo domain.CacheRepository,
	pipeline domain.EventPipeline,
) *ChatUsecase {
	return &ChatUsecase{
		chatRepo:  chatRepo,
		roomRepo:  roomRepo,
		cacheRepo: cacheRepo,
		pipeline:  pipeline,
	}
}

// GetOrCreateRoom fetches or creates a mutually unique active chat room for the two users.
func (u *ChatUsecase) GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error) {
	return u.roomRepo.GetOrCreateRoom(ctx, userA, userB)
}


// ProcessIncomingMessage checks idempotency, persists the message, and publishes it to the Kafka pipeline.
func (u *ChatUsecase) ProcessIncomingMessage(ctx context.Context, senderID string, msg *domain.Message) error {
	// 1. Idempotency Check (prevent duplicates)
	if msg.IdempotencyKey != "" {
		unique, err := u.cacheRepo.SetIdempotencyKey(ctx, msg.IdempotencyKey, 1*time.Hour)
		if err != nil {
			return err
		}
		if !unique {
			// Duplicate message detected; ignore processing but return success to avoid retries
			return nil
		}
	}

	// Set sender ID and timestamp
	msg.SenderID = senderID
	if msg.CreatedAt.IsZero() {
		msg.CreatedAt = time.Now()
	}

	// 2. Persist message to PostgreSQL
	if err := u.chatRepo.SaveMessage(ctx, msg); err != nil {
		return err
	}

	// 3. Publish to Kafka event pipeline
	event := &domain.EventPacket{
		Type:     "MESSAGE",
		SenderID: senderID,
		RoomID:   msg.RoomID,
		Message:  msg,
	}

	return u.pipeline.PublishChatEvent(ctx, event)
}

// ProcessReadReceipt persists the read receipt and publishes the event to the Kafka pipeline.
func (u *ChatUsecase) ProcessReadReceipt(ctx context.Context, userID string, receipt *domain.ReadReceipt) error {
	receipt.UserID = userID
	if receipt.Timestamp.IsZero() {
		receipt.Timestamp = time.Now()
	}

	// 1. Persist receipt to PostgreSQL
	if err := u.chatRepo.SaveReceipt(ctx, receipt); err != nil {
		return err
	}

	// 2. Publish receipt event to Kafka
	event := &domain.EventPacket{
		Type:     "RECEIPT",
		SenderID: userID,
		RoomID:   receipt.RoomID,
		Receipt:  receipt,
	}

	return u.pipeline.PublishChatEvent(ctx, event)
}

// ProcessTyping routes high-frequency transient typing events directly via Redis Pub/Sub.
func (u *ChatUsecase) ProcessTyping(ctx context.Context, userID string, typing *domain.TypingIndicator) error {
	typing.UserID = userID
	return u.cacheRepo.PublishTyping(ctx, typing)
}

// SetUserOnline updates the online status of a user.
func (u *ChatUsecase) SetUserOnline(ctx context.Context, userID string, isOnline bool) error {
	return u.cacheRepo.SetUserOnline(ctx, userID, isOnline)
}

// GetOfflineHistory retrieves all messages from active rooms created after the reconnect timestamp with pagination.
func (u *ChatUsecase) GetOfflineHistory(ctx context.Context, userID string, since time.Time, limit, offset int) ([]*domain.Message, error) {
	// 1. Fetch user's active rooms
	rooms, err := u.chatRepo.GetActiveRoomsForUser(ctx, userID)
	if err != nil {
		return nil, err
	}

	if len(rooms) == 0 {
		return []*domain.Message{}, nil
	}

	if limit <= 0 {
		limit = 100 // Default limit to avoid massive initial recovery payloads
	}
	if offset < 0 {
		offset = 0
	}

	// 2. Query messages since timestamp across all rooms in a single query with pagination
	return u.chatRepo.GetRoomsMessagesSince(ctx, rooms, since, limit, offset)
}

// SubscribeRoomTyping subscribes to transient room typing indicators from the cache repository.
func (u *ChatUsecase) SubscribeRoomTyping(ctx context.Context, roomID string) (<-chan *domain.TypingIndicator, func() error, error) {
	return u.cacheRepo.SubscribeRoomTyping(ctx, roomID)
}

