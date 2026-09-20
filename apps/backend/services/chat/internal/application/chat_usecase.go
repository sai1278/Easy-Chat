package application

import (
	"context"
	"fmt"
	"time"

	"nearby/backend/services/chat/internal/domain"
)

// ChatUsecase orchestrates the chat messaging, receipt processing, typing indicators, history recovery, and chat request lifecycle.
type ChatUsecase struct {
	chatRepo    domain.ChatRepository
	roomRepo    domain.RoomRepository
	requestRepo domain.RequestRepository
	cacheRepo   domain.CacheRepository
	pipeline    domain.EventPipeline
}

// NewChatUsecase creates a new ChatUsecase.
func NewChatUsecase(
	chatRepo domain.ChatRepository,
	roomRepo domain.RoomRepository,
	requestRepo domain.RequestRepository,
	cacheRepo domain.CacheRepository,
	pipeline domain.EventPipeline,
) *ChatUsecase {
	return &ChatUsecase{
		chatRepo:    chatRepo,
		roomRepo:    roomRepo,
		requestRepo: requestRepo,
		cacheRepo:   cacheRepo,
		pipeline:    pipeline,
	}
}

// GetOrCreateRoom fetches or creates a mutually unique active chat room for the two users.
func (u *ChatUsecase) GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error) {
	return u.roomRepo.GetOrCreateRoom(ctx, userA, userB)
}

// ProcessIncomingMessage checks room active status & chat request acceptance, checks idempotency, persists the message, and publishes it to the Kafka pipeline.
func (u *ChatUsecase) ProcessIncomingMessage(ctx context.Context, senderID string, msg *domain.Message) error {
	// Guard: Message blocked if room is not active or chat request is denied / pending
	if u.requestRepo != nil {
		active, err := u.requestRepo.IsRoomActiveAndAccepted(ctx, msg.RoomID)
		if err != nil {
			return fmt.Errorf("failed to verify chat room status: %w", err)
		}
		if !active {
			return fmt.Errorf("messaging blocked: chat request is not accepted or room is inactive")
		}
	}

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

// CreateChatRequest creates a new PENDING request from sender to recipient and dispatches a notification event.
func (u *ChatUsecase) CreateChatRequest(ctx context.Context, senderID, recipientID string) (*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}

	req, err := u.requestRepo.CreateRequest(ctx, senderID, recipientID)
	if err != nil {
		return nil, err
	}

	// Notify recipient via event pipeline
	event := &domain.EventPacket{
		Type:        "CHAT_REQUEST_RECEIVED",
		SenderID:    senderID,
		RoomID:      req.RoomID,
		ChatRequest: req,
	}
	_ = u.pipeline.PublishChatEvent(ctx, event)

	return req, nil
}

// GetPendingRequests returns all pending chat requests for a user.
func (u *ChatUsecase) GetPendingRequests(ctx context.Context, userID string) ([]*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}
	return u.requestRepo.GetPendingRequestsForUser(ctx, userID)
}

// GetChatRequestByID retrieves a single chat request by ID.
func (u *ChatUsecase) GetChatRequestByID(ctx context.Context, requestID string) (*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}
	return u.requestRepo.GetRequestByID(ctx, requestID)
}

// GetChatRequestBetweenUsers retrieves the active/latest request between two users.
func (u *ChatUsecase) GetChatRequestBetweenUsers(ctx context.Context, userA, userB string) (*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}
	return u.requestRepo.GetRequestBetweenUsers(ctx, userA, userB)
}

// AcceptChatRequest accepts a pending chat request, activating the room and notifying participants.
func (u *ChatUsecase) AcceptChatRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}

	req, err := u.requestRepo.AcceptRequest(ctx, requestID, recipientID)
	if err != nil {
		return nil, err
	}

	// Notify both users
	event := &domain.EventPacket{
		Type:        "CHAT_REQUEST_ACCEPTED",
		SenderID:    recipientID,
		RoomID:      req.RoomID,
		ChatRequest: req,
	}
	_ = u.pipeline.PublishChatEvent(ctx, event)

	return req, nil
}

// DenyChatRequest denies a pending chat request, closing any room and notifying participants.
func (u *ChatUsecase) DenyChatRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	if u.requestRepo == nil {
		return nil, fmt.Errorf("request repository not initialized")
	}

	req, err := u.requestRepo.DenyRequest(ctx, requestID, recipientID)
	if err != nil {
		return nil, err
	}

	// Notify both users
	event := &domain.EventPacket{
		Type:        "CHAT_REQUEST_DENIED",
		SenderID:    recipientID,
		RoomID:      req.RoomID,
		ChatRequest: req,
	}
	_ = u.pipeline.PublishChatEvent(ctx, event)

	return req, nil
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

// GetOfflineDeletions retrieves message IDs deleted since reconnect timestamp for offline synchronization.
func (u *ChatUsecase) GetOfflineDeletions(ctx context.Context, userID string, since time.Time) ([]string, error) {
	rooms, err := u.chatRepo.GetActiveRoomsForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	if len(rooms) == 0 {
		return []string{}, nil
	}
	return u.chatRepo.GetDeletedMessagesSince(ctx, rooms, since)
}

// DeleteMessageForEveryone authorizes and executes durable deletion of a message across all clients.
func (u *ChatUsecase) DeleteMessageForEveryone(ctx context.Context, userID, messageID, roomID string) error {
	// 1. Verify user is a member of the room
	members, err := u.roomRepo.GetMembers(ctx, roomID)
	if err != nil {
		return fmt.Errorf("failed to verify room membership: %w", err)
	}
	isMember := false
	for _, m := range members {
		if m == userID {
			isMember = true
			break
		}
	}
	if !isMember {
		return fmt.Errorf("unauthorized: user %s is not a member of room %s", userID, roomID)
	}

	// 2. Execute deletion in PostgreSQL (enforces sender_id == userID)
	if err := u.chatRepo.DeleteMessageForEveryone(ctx, messageID, roomID, userID); err != nil {
		return fmt.Errorf("failed to delete message: %w", err)
	}

	// 3. Publish deletion tombstone to Kafka event pipeline
	event := &domain.EventPacket{
		Type:     "MESSAGE_DELETED",
		SenderID: userID,
		RoomID:   roomID,
		DeleteMessage: &domain.DeleteMessageEvent{
			MessageID: messageID,
			RoomID:    roomID,
		},
	}
	return u.pipeline.PublishChatEvent(ctx, event)
}

// RegisterCryptoIdentity registers or updates a user's public identity and signed prekey.
func (u *ChatUsecase) RegisterCryptoIdentity(ctx context.Context, identity *domain.UserCryptoIdentity) error {
	if identity.UserID == "" || identity.IdentityKeyPub == "" || identity.SignedPrekeyPub == "" {
		return fmt.Errorf("invalid crypto identity: missing required fields")
	}
	return u.chatRepo.SaveCryptoIdentity(ctx, identity)
}

// GetCryptoIdentity fetches a user's public crypto identity for E2EE session agreement.
func (u *ChatUsecase) GetCryptoIdentity(ctx context.Context, userID string) (*domain.UserCryptoIdentity, error) {
	if userID == "" {
		return nil, fmt.Errorf("missing user ID")
	}
	return u.chatRepo.GetCryptoIdentity(ctx, userID)
}

// SubscribeRoomTyping subscribes to transient room typing indicators from the cache repository.
func (u *ChatUsecase) SubscribeRoomTyping(ctx context.Context, roomID string) (<-chan *domain.TypingIndicator, func() error, error) {
	return u.cacheRepo.SubscribeRoomTyping(ctx, roomID)
}

