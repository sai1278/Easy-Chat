package application

import (
	"context"
	"sync"
	"testing"
	"time"

	"nearby/backend/services/chat/internal/domain"
)

// MockChatRepository implements domain.ChatRepository.
type MockChatRepository struct {
	mu          sync.Mutex
	messages    []*domain.Message
	receipts    []*domain.ReadReceipt
	activeRooms map[string][]string
}

func (m *MockChatRepository) SaveMessage(ctx context.Context, msg *domain.Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.messages = append(m.messages, msg)
	return nil
}

func (m *MockChatRepository) SaveReceipt(ctx context.Context, receipt *domain.ReadReceipt) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.receipts = append(m.receipts, receipt)
	return nil
}

func (m *MockChatRepository) GetRoomMessagesSince(ctx context.Context, roomID string, since time.Time) ([]*domain.Message, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var res []*domain.Message
	for _, msg := range m.messages {
		if msg.RoomID == roomID && msg.CreatedAt.After(since) {
			res = append(res, msg)
		}
	}
	return res, nil
}

func (m *MockChatRepository) GetRoomsMessagesSince(ctx context.Context, roomIDs []string, since time.Time, limit, offset int) ([]*domain.Message, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var res []*domain.Message
	roomsSet := make(map[string]bool)
	for _, id := range roomIDs {
		roomsSet[id] = true
	}
	count := 0
	skipped := 0
	for _, msg := range m.messages {
		if roomsSet[msg.RoomID] && msg.CreatedAt.After(since) {
			if skipped < offset {
				skipped++
				continue
			}
			res = append(res, msg)
			count++
			if limit > 0 && count >= limit {
				break
			}
		}
	}
	return res, nil
}

func (m *MockChatRepository) GetActiveRoomsForUser(ctx context.Context, userID string) ([]string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.activeRooms[userID], nil
}

// MockCacheRepository implements domain.CacheRepository.
type MockCacheRepository struct {
	mu        sync.Mutex
	idempKeys map[string]bool
	typing    []*domain.TypingIndicator
	online    map[string]bool
}

func (m *MockCacheRepository) SetIdempotencyKey(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.idempKeys[key] {
		return false, nil
	}
	m.idempKeys[key] = true
	return true, nil
}

func (m *MockCacheRepository) PublishTyping(ctx context.Context, indicator *domain.TypingIndicator) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.typing = append(m.typing, indicator)
	return nil
}

func (m *MockCacheRepository) SubscribeRoomTyping(ctx context.Context, roomID string) (<-chan *domain.TypingIndicator, func() error, error) {
	ch := make(chan *domain.TypingIndicator, 10)
	cleanup := func() error { return nil }
	return ch, cleanup, nil
}

func (m *MockCacheRepository) SetUserOnline(ctx context.Context, userID string, isOnline bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.online[userID] = isOnline
	return nil
}

func (m *MockCacheRepository) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.online[userID], nil
}

// MockEventPipeline implements domain.EventPipeline.
type MockEventPipeline struct {
	mu     sync.Mutex
	events []*domain.EventPacket
}

func (m *MockEventPipeline) PublishChatEvent(ctx context.Context, event *domain.EventPacket) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.events = append(m.events, event)
	return nil
}

func (m *MockEventPipeline) ConsumeChatEvents(ctx context.Context) (<-chan *domain.EventPacket, error) {
	ch := make(chan *domain.EventPacket)
	return ch, nil
}

func (m *MockEventPipeline) Close() error {
	return nil
}

// MockRoomRepository implements domain.RoomRepository.
type MockRoomRepository struct {
	mu    sync.Mutex
	rooms map[string][]string
}

func (m *MockRoomRepository) GetMembers(ctx context.Context, roomID string) ([]string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.rooms[roomID], nil
}

func (m *MockRoomRepository) GetOrCreateRoom(ctx context.Context, userA, userB string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.rooms == nil {
		m.rooms = make(map[string][]string)
	}
	for rID, members := range m.rooms {
		if (members[0] == userA && members[1] == userB) || (members[0] == userB && members[1] == userA) {
			return rID, nil
		}
	}
	rID := "mock-room-uuid"
	m.rooms[rID] = []string{userA, userB}
	return rID, nil
}

func TestChatUsecase_ProcessIncomingMessage_Success(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, cacheRepo, pipeline)

	msg := &domain.Message{
		ID:               "msg-1",
		RoomID:           "room-123",
		EncryptedPayload: []byte("hello"),
		IdempotencyKey:   "key-abc",
		CreatedAt:        time.Now(),
	}

	err := usecase.ProcessIncomingMessage(context.Background(), "user-alice", msg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify Postgres persistence
	if len(chatRepo.messages) != 1 {
		t.Errorf("expected 1 message stored, got %d", len(chatRepo.messages))
	}
	if chatRepo.messages[0].SenderID != "user-alice" {
		t.Errorf("expected sender to be user-alice, got %s", chatRepo.messages[0].SenderID)
	}

	// Verify Kafka pipeline publish
	if len(pipeline.events) != 1 {
		t.Errorf("expected 1 event published, got %d", len(pipeline.events))
	}
	if pipeline.events[0].Type != "MESSAGE" {
		t.Errorf("expected event type MESSAGE, got %s", pipeline.events[0].Type)
	}
}

func TestChatUsecase_ProcessIncomingMessage_Idempotency(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, cacheRepo, pipeline)

	msg := &domain.Message{
		ID:               "msg-1",
		RoomID:           "room-123",
		EncryptedPayload: []byte("hello"),
		IdempotencyKey:   "key-abc",
		CreatedAt:        time.Now(),
	}

	// First delivery
	err := usecase.ProcessIncomingMessage(context.Background(), "user-alice", msg)
	if err != nil {
		t.Fatalf("first delivery failed: %v", err)
	}

	// Second duplicate delivery
	err2 := usecase.ProcessIncomingMessage(context.Background(), "user-alice", msg)
	if err2 != nil {
		t.Fatalf("duplicate delivery returned error: %v", err2)
	}

	// Verify that the message was only stored and published ONCE
	if len(chatRepo.messages) != 1 {
		t.Errorf("expected exactly 1 stored message due to idempotency, got %d", len(chatRepo.messages))
	}
	if len(pipeline.events) != 1 {
		t.Errorf("expected exactly 1 published event due to idempotency, got %d", len(pipeline.events))
	}
}

func TestChatUsecase_ProcessReadReceipt(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	cacheRepo := &MockCacheRepository{}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, cacheRepo, pipeline)

	receipt := &domain.ReadReceipt{
		MessageID: "msg-1",
		RoomID:    "room-123",
		Status:    "READ",
	}

	err := usecase.ProcessReadReceipt(context.Background(), "user-bob", receipt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(chatRepo.receipts) != 1 {
		t.Errorf("expected 1 receipt stored, got %d", len(chatRepo.receipts))
	}
	if chatRepo.receipts[0].UserID != "user-bob" {
		t.Errorf("expected receipt user to be user-bob, got %s", chatRepo.receipts[0].UserID)
	}

	if len(pipeline.events) != 1 {
		t.Errorf("expected 1 published event, got %d", len(pipeline.events))
	}
	if pipeline.events[0].Type != "RECEIPT" {
		t.Errorf("expected event type RECEIPT, got %s", pipeline.events[0].Type)
	}
}

func TestChatUsecase_ProcessTyping(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	cacheRepo := &MockCacheRepository{}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, cacheRepo, pipeline)

	typing := &domain.TypingIndicator{
		RoomID:   "room-123",
		IsTyping: true,
	}

	err := usecase.ProcessTyping(context.Background(), "user-alice", typing)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Typing should go directly to cache pub/sub, not DB or Kafka pipeline
	if len(cacheRepo.typing) != 1 {
		t.Errorf("expected 1 transient typing event published, got %d", len(cacheRepo.typing))
	}
	if cacheRepo.typing[0].UserID != "user-alice" {
		t.Errorf("expected typing user to be user-alice, got %s", cacheRepo.typing[0].UserID)
	}
}

func TestChatUsecase_ReconnectRecovery(t *testing.T) {
	now := time.Now()
	chatRepo := &MockChatRepository{
		activeRooms: map[string][]string{
			"user-alice": {"room-1", "room-2"},
		},
		messages: []*domain.Message{
			{ID: "msg-old", RoomID: "room-1", CreatedAt: now.Add(-10 * time.Minute)},
			{ID: "msg-new-1", RoomID: "room-1", CreatedAt: now.Add(5 * time.Minute)},
			{ID: "msg-new-2", RoomID: "room-2", CreatedAt: now.Add(8 * time.Minute)},
		},
	}
	roomRepo := &MockRoomRepository{}
	cacheRepo := &MockCacheRepository{}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, cacheRepo, pipeline)

	// Recover since now (should get msg-new-1 and msg-new-2, but not msg-old)
	history, err := usecase.GetOfflineHistory(context.Background(), "user-alice", now, 100, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(history) != 2 {
		t.Fatalf("expected 2 history messages, got %d", len(history))
	}

	msgIDs := map[string]bool{
		history[0].ID: true,
		history[1].ID: true,
	}

	if !msgIDs["msg-new-1"] || !msgIDs["msg-new-2"] {
		t.Errorf("returned history did not contain correct recovered messages: %v", history)
	}
}
