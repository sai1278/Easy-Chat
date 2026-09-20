package application

import (
	"context"
	"errors"
	"fmt"
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

func (m *MockChatRepository) GetMessageByID(ctx context.Context, messageID, roomID string) (*domain.Message, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, msg := range m.messages {
		if msg.ID == messageID && msg.RoomID == roomID {
			return msg, nil
		}
	}
	return nil, errors.New("message not found")
}

func (m *MockChatRepository) DeleteMessageForEveryone(ctx context.Context, messageID, roomID, senderID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, msg := range m.messages {
		if msg.ID == messageID && msg.RoomID == roomID {
			if msg.SenderID != senderID {
				return errors.New("unauthorized: sender mismatch")
			}
			if msg.IsDeleted {
				return errors.New("message already deleted")
			}
			msg.IsDeleted = true
			now := time.Now()
			msg.DeletedAt = &now
			msg.EncryptedPayload = []byte{}
			return nil
		}
	}
	return errors.New("message not found")
}

func (m *MockChatRepository) GetDeletedMessagesSince(ctx context.Context, roomIDs []string, since time.Time) ([]string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var res []string
	roomsSet := make(map[string]bool)
	for _, id := range roomIDs {
		roomsSet[id] = true
	}
	for _, msg := range m.messages {
		if roomsSet[msg.RoomID] && msg.IsDeleted && msg.DeletedAt != nil && msg.DeletedAt.After(since) {
			res = append(res, msg.ID)
		}
	}
	return res, nil
}

func (m *MockChatRepository) SaveCryptoIdentity(ctx context.Context, identity *domain.UserCryptoIdentity) error {
	return nil
}

func (m *MockChatRepository) GetCryptoIdentity(ctx context.Context, userID string) (*domain.UserCryptoIdentity, error) {
	return &domain.UserCryptoIdentity{
		UserID:          userID,
		IdentityKeyPub:  "test-ik",
		SignedPrekeyPub: "test-spk",
		SignedPrekeySig: "test-sig",
	}, nil
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

func (m *MockRoomRepository) IsRoomActive(ctx context.Context, roomID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, exists := m.rooms[roomID]
	return exists, nil
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

// MockRequestRepository implements domain.RequestRepository.
type MockRequestRepository struct {
	mu             sync.Mutex
	requests       map[string]*domain.ChatRequest
	roomActiveMap  map[string]bool
	existingUsers  map[string]bool
}

func NewMockRequestRepository() *MockRequestRepository {
	return &MockRequestRepository{
		requests:      make(map[string]*domain.ChatRequest),
		roomActiveMap: make(map[string]bool),
		existingUsers: map[string]bool{
			"user-alice": true,
			"user-bob":   true,
			"user-charlie": true,
		},
	}
}

func (m *MockRequestRepository) CreateRequest(ctx context.Context, senderID, recipientID string) (*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if senderID == recipientID {
		return nil, errors.New("sender and recipient cannot be the same user")
	}
	if !m.existingUsers[senderID] || !m.existingUsers[recipientID] {
		return nil, errors.New("one or both users do not exist")
	}

	for _, r := range m.requests {
		if (r.SenderID == senderID && r.RecipientID == recipientID) || (r.SenderID == recipientID && r.RecipientID == senderID) {
			if r.Status == domain.RequestStatusPending || r.Status == domain.RequestStatusAccepted {
				return r, nil // Idempotent/duplicate protection
			}
		}
	}

	reqID := fmt.Sprintf("req-%d", len(m.requests)+1)
	now := time.Now()
	req := &domain.ChatRequest{
		ID:                reqID,
		SenderID:          senderID,
		RecipientID:       recipientID,
		Status:            domain.RequestStatusPending,
		CreatedAt:         now,
		UpdatedAt:         now,
		SenderDisplayName: "Sender " + senderID,
	}
	m.requests[reqID] = req
	return req, nil
}

func (m *MockRequestRepository) GetPendingRequestsForUser(ctx context.Context, recipientID string) ([]*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var list []*domain.ChatRequest
	for _, r := range m.requests {
		if r.RecipientID == recipientID && r.Status == domain.RequestStatusPending {
			list = append(list, r)
		}
	}
	return list, nil
}

func (m *MockRequestRepository) GetRequestByID(ctx context.Context, requestID string) (*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, exists := m.requests[requestID]
	if !exists {
		return nil, errors.New("request not found")
	}
	return r, nil
}

func (m *MockRequestRepository) GetRequestBetweenUsers(ctx context.Context, userA, userB string) (*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.requests {
		if (r.SenderID == userA && r.RecipientID == userB) || (r.SenderID == userB && r.RecipientID == userA) {
			return r, nil
		}
	}
	return nil, nil
}

func (m *MockRequestRepository) AcceptRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	req, exists := m.requests[requestID]
	if !exists {
		return nil, errors.New("request not found")
	}
	if req.RecipientID != recipientID {
		return nil, errors.New("unauthorized: only recipient can accept")
	}
	if req.Status == domain.RequestStatusAccepted {
		return nil, errors.New("request already accepted")
	}
	if req.Status == domain.RequestStatusDenied {
		return nil, errors.New("cannot accept an already denied request")
	}
	if req.Status != domain.RequestStatusPending {
		return nil, fmt.Errorf("cannot accept request in %s status", req.Status)
	}

	roomID := fmt.Sprintf("room-%s-%s", req.SenderID, req.RecipientID)
	now := time.Now()
	req.Status = domain.RequestStatusAccepted
	req.RoomID = roomID
	req.RespondedAt = &now
	req.UpdatedAt = now
	m.roomActiveMap[roomID] = true

	return req, nil
}

func (m *MockRequestRepository) DenyRequest(ctx context.Context, requestID, recipientID string) (*domain.ChatRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	req, exists := m.requests[requestID]
	if !exists {
		return nil, errors.New("request not found")
	}
	if req.RecipientID != recipientID {
		return nil, errors.New("unauthorized: only recipient can deny")
	}
	if req.Status == domain.RequestStatusAccepted {
		return nil, errors.New("cannot deny an already accepted request")
	}
	if req.Status == domain.RequestStatusDenied {
		return nil, errors.New("request already denied")
	}
	if req.Status != domain.RequestStatusPending {
		return nil, fmt.Errorf("cannot deny request in %s status", req.Status)
	}

	now := time.Now()
	req.Status = domain.RequestStatusDenied
	req.RespondedAt = &now
	req.UpdatedAt = now
	if req.RoomID != "" {
		m.roomActiveMap[req.RoomID] = false
	}

	return req, nil
}

func (m *MockRequestRepository) IsRoomActiveAndAccepted(ctx context.Context, roomID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.roomActiveMap[roomID], nil
}

// ==========================================
// Tests
// ==========================================

func TestChatUsecase_ProcessIncomingMessage_Success(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	reqRepo := NewMockRequestRepository()
	reqRepo.roomActiveMap["room-123"] = true
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, reqRepo, cacheRepo, pipeline)

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

	if len(chatRepo.messages) != 1 {
		t.Errorf("expected 1 message stored, got %d", len(chatRepo.messages))
	}
	if chatRepo.messages[0].SenderID != "user-alice" {
		t.Errorf("expected sender to be user-alice, got %s", chatRepo.messages[0].SenderID)
	}

	if len(pipeline.events) != 1 {
		t.Errorf("expected 1 event published, got %d", len(pipeline.events))
	}
	if pipeline.events[0].Type != "MESSAGE" {
		t.Errorf("expected event type MESSAGE, got %s", pipeline.events[0].Type)
	}
}

func TestChatUsecase_ProcessIncomingMessage_BlockedWhenInactiveOrDenied(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	reqRepo := NewMockRequestRepository()
	reqRepo.roomActiveMap["room-inactive"] = false // Not active / denied
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, reqRepo, cacheRepo, pipeline)

	msg := &domain.Message{
		ID:               "msg-blocked",
		RoomID:           "room-inactive",
		EncryptedPayload: []byte("should not pass"),
		IdempotencyKey:   "key-blocked",
		CreatedAt:        time.Now(),
	}

	err := usecase.ProcessIncomingMessage(context.Background(), "user-alice", msg)
	if err == nil {
		t.Fatalf("expected error for inactive/denied room, but got nil")
	}

	if len(chatRepo.messages) != 0 {
		t.Errorf("expected 0 messages stored, got %d", len(chatRepo.messages))
	}
}

func TestChatUsecase_ChatRequest_Lifecycle(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	reqRepo := NewMockRequestRepository()
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, reqRepo, cacheRepo, pipeline)
	ctx := context.Background()

	// 1. Self request prevention
	_, err := usecase.CreateChatRequest(ctx, "user-alice", "user-alice")
	if err == nil {
		t.Errorf("expected error when sending chat request to self, got nil")
	}

	// 2. User A sends request to User B
	req, err := usecase.CreateChatRequest(ctx, "user-alice", "user-bob")
	if err != nil {
		t.Fatalf("failed to create chat request: %v", err)
	}
	if req.Status != domain.RequestStatusPending {
		t.Errorf("expected status PENDING, got %s", req.Status)
	}
	if len(pipeline.events) != 1 || pipeline.events[0].Type != "CHAT_REQUEST_RECEIVED" {
		t.Errorf("expected CHAT_REQUEST_RECEIVED event published")
	}

	// 3. Duplicate request check (should return existing pending request)
	dupReq, err := usecase.CreateChatRequest(ctx, "user-alice", "user-bob")
	if err != nil {
		t.Fatalf("failed on duplicate request: %v", err)
	}
	if dupReq.ID != req.ID {
		t.Errorf("expected same request ID %s, got %s", req.ID, dupReq.ID)
	}

	// 4. Pending request retrieval for User B
	pendingList, err := usecase.GetPendingRequests(ctx, "user-bob")
	if err != nil {
		t.Fatalf("failed to get pending requests: %v", err)
	}
	if len(pendingList) != 1 || pendingList[0].ID != req.ID {
		t.Errorf("expected 1 pending request with ID %s", req.ID)
	}

	// 5. Unauthorized Accept (Sender alice tries to accept own request)
	_, err = usecase.AcceptChatRequest(ctx, req.ID, "user-alice")
	if err == nil {
		t.Errorf("expected error when sender tries to accept own request")
	}

	// 6. User B accepts request
	acceptedReq, err := usecase.AcceptChatRequest(ctx, req.ID, "user-bob")
	if err != nil {
		t.Fatalf("failed to accept chat request: %v", err)
	}
	if acceptedReq.Status != domain.RequestStatusAccepted {
		t.Errorf("expected status ACCEPTED, got %s", acceptedReq.Status)
	}
	if acceptedReq.RoomID == "" {
		t.Errorf("expected room ID on accepted request")
	}

	// Verify WebSocket accept event published
	var foundAcceptEvt bool
	for _, evt := range pipeline.events {
		if evt.Type == "CHAT_REQUEST_ACCEPTED" {
			foundAcceptEvt = true
			break
		}
	}
	if !foundAcceptEvt {
		t.Errorf("expected CHAT_REQUEST_ACCEPTED event published")
	}

	// 7. Duplicate Accept prevention
	_, err = usecase.AcceptChatRequest(ctx, req.ID, "user-bob")
	if err == nil {
		t.Errorf("expected error on duplicate accept")
	}

	// 8. Deny after Acceptance prevention
	_, err = usecase.DenyChatRequest(ctx, req.ID, "user-bob")
	if err == nil {
		t.Errorf("expected error when denying an already accepted request")
	}

	// 9. Messaging allowed now that request is accepted
	msg := &domain.Message{
		ID:               "msg-accepted",
		RoomID:           acceptedReq.RoomID,
		EncryptedPayload: []byte("Hello from Alice! 😊"),
		CreatedAt:        time.Now(),
	}
	err = usecase.ProcessIncomingMessage(ctx, "user-alice", msg)
	if err != nil {
		t.Fatalf("expected message to succeed after acceptance, got error: %v", err)
	}
}

func TestChatUsecase_ChatRequest_DenialFlow(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	reqRepo := NewMockRequestRepository()
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, reqRepo, cacheRepo, pipeline)
	ctx := context.Background()

	// 1. User A sends request to User C
	req, err := usecase.CreateChatRequest(ctx, "user-alice", "user-charlie")
	if err != nil {
		t.Fatalf("failed to create request: %v", err)
	}

	// 2. Unauthorized Deny (Alice tries to deny own request)
	_, err = usecase.DenyChatRequest(ctx, req.ID, "user-alice")
	if err == nil {
		t.Errorf("expected error when sender tries to deny own request")
	}

	// 3. Recipient Charlie denies request
	deniedReq, err := usecase.DenyChatRequest(ctx, req.ID, "user-charlie")
	if err != nil {
		t.Fatalf("failed to deny request: %v", err)
	}
	if deniedReq.Status != domain.RequestStatusDenied {
		t.Errorf("expected status DENIED, got %s", deniedReq.Status)
	}

	// Verify WebSocket deny event published
	var foundDenyEvt bool
	for _, evt := range pipeline.events {
		if evt.Type == "CHAT_REQUEST_DENIED" {
			foundDenyEvt = true
			break
		}
	}
	if !foundDenyEvt {
		t.Errorf("expected CHAT_REQUEST_DENIED event published")
	}

	// 4. Duplicate Deny prevention
	_, err = usecase.DenyChatRequest(ctx, req.ID, "user-charlie")
	if err == nil {
		t.Errorf("expected error on duplicate deny")
	}

	// 5. Accept after Denial prevention
	_, err = usecase.AcceptChatRequest(ctx, req.ID, "user-charlie")
	if err == nil {
		t.Errorf("expected error on accept after denial")
	}

	// 6. Messaging blocked for denied session
	msg := &domain.Message{
		ID:               "msg-denied",
		RoomID:           "room-alice-charlie",
		EncryptedPayload: []byte("Forbidden message"),
		CreatedAt:        time.Now(),
	}
	err = usecase.ProcessIncomingMessage(ctx, "user-alice", msg)
	if err == nil {
		t.Fatalf("expected message to be blocked for denied request, but got nil")
	}
}

func TestChatUsecase_UTF8Persistence(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{}
	reqRepo := NewMockRequestRepository()
	reqRepo.roomActiveMap["room-utf8"] = true
	cacheRepo := &MockCacheRepository{idempKeys: make(map[string]bool)}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, reqRepo, cacheRepo, pipeline)

	testPayloads := []string{
		"Hello from Device A",
		"😀 😃 😄 😁 ❤️ 👍 👋 🚀 🔥 🎉",
		"नमस्ते 👋 مرحبا 🌍 你好 😊",
		"! @ # $ % ^ & * ( ) _ - + = [ ] { } ; : ' \" , . < > / ?",
		"€ ₹ ¥ £ © ® ™ → ← ↑ ↓ ✓ ✗ • … §",
		"Hello 😀! Welcome to Easy Chat 🚀 - ₹100 + $20 = €110",
	}

	for i, payload := range testPayloads {
		msg := &domain.Message{
			ID:               fmt.Sprintf("msg-utf8-%d", i),
			RoomID:           "room-utf8",
			EncryptedPayload: []byte(payload),
			IdempotencyKey:   fmt.Sprintf("idemp-%d", i),
			CreatedAt:        time.Now(),
		}

		err := usecase.ProcessIncomingMessage(context.Background(), "user-alice", msg)
		if err != nil {
			t.Fatalf("failed to process UTF-8 payload %q: %v", payload, err)
		}

		// Verify stored bytes match exactly
		stored := string(chatRepo.messages[i].EncryptedPayload)
		if stored != payload {
			t.Errorf("UTF-8 corrupted! Expected %q, got %q", payload, stored)
		}
	}
}

func TestDeleteMessageForEveryone_Success(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{
		rooms: map[string][]string{
			"room-100": {"user-alice", "user-bob"},
		},
	}
	cacheRepo := &MockCacheRepository{
		idempKeys: make(map[string]bool),
		online:    make(map[string]bool),
	}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, nil, cacheRepo, pipeline)

	// Seed message
	msg := &domain.Message{
		ID:               "msg-to-delete",
		RoomID:           "room-100",
		SenderID:         "user-alice",
		EncryptedPayload: []byte("secret e2ee ciphertext"),
		CreatedAt:        time.Now(),
	}
	chatRepo.messages = append(chatRepo.messages, msg)

	// Alice deletes her message
	err := usecase.DeleteMessageForEveryone(context.Background(), "user-alice", "msg-to-delete", "room-100")
	if err != nil {
		t.Fatalf("expected deletion to succeed, got %v", err)
	}

	// Verify message in repo is marked deleted and payload is wiped
	if !msg.IsDeleted {
		t.Errorf("expected msg.IsDeleted to be true")
	}
	if len(msg.EncryptedPayload) != 0 {
		t.Errorf("expected msg.EncryptedPayload to be wiped, got len %d", len(msg.EncryptedPayload))
	}

	// Verify MESSAGE_DELETED event published to pipeline
	if len(pipeline.events) != 1 {
		t.Fatalf("expected 1 event published, got %d", len(pipeline.events))
	}
	evt := pipeline.events[0]
	if evt.Type != "MESSAGE_DELETED" || evt.DeleteMessage.MessageID != "msg-to-delete" {
		t.Errorf("unexpected event published: %+v", evt)
	}
}

func TestDeleteMessageForEveryone_UnauthorizedNonMember(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{
		rooms: map[string][]string{
			"room-100": {"user-alice", "user-bob"},
		},
	}
	cacheRepo := &MockCacheRepository{
		idempKeys: make(map[string]bool),
		online:    make(map[string]bool),
	}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, nil, cacheRepo, pipeline)

	// Mallory is not in room-100
	err := usecase.DeleteMessageForEveryone(context.Background(), "user-mallory", "msg-to-delete", "room-100")
	if err == nil {
		t.Fatalf("expected error for non-member, got nil")
	}
}

func TestDeleteMessageForEveryone_NonOwner(t *testing.T) {
	chatRepo := &MockChatRepository{}
	roomRepo := &MockRoomRepository{
		rooms: map[string][]string{
			"room-100": {"user-alice", "user-bob"},
		},
	}
	cacheRepo := &MockCacheRepository{
		idempKeys: make(map[string]bool),
		online:    make(map[string]bool),
	}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, nil, cacheRepo, pipeline)

	// Alice sends message
	msg := &domain.Message{
		ID:               "msg-alice-secret",
		RoomID:           "room-100",
		SenderID:         "user-alice",
		EncryptedPayload: []byte("secret"),
		CreatedAt:        time.Now(),
	}
	chatRepo.messages = append(chatRepo.messages, msg)

	// Bob tries to delete Alice's message for everyone (must fail!)
	err := usecase.DeleteMessageForEveryone(context.Background(), "user-bob", "msg-alice-secret", "room-100")
	if err == nil {
		t.Fatalf("expected error when non-owner tries to delete for everyone, got nil")
	}
}

func TestOfflineDeletions_Sync(t *testing.T) {
	chatRepo := &MockChatRepository{
		activeRooms: map[string][]string{
			"user-bob": {"room-100"},
		},
	}
	roomRepo := &MockRoomRepository{
		rooms: map[string][]string{
			"room-100": {"user-alice", "user-bob"},
		},
	}
	cacheRepo := &MockCacheRepository{
		idempKeys: make(map[string]bool),
		online:    make(map[string]bool),
	}
	pipeline := &MockEventPipeline{}
	usecase := NewChatUsecase(chatRepo, roomRepo, nil, cacheRepo, pipeline)

	since := time.Now().Add(-10 * time.Minute)
	deletedAt := time.Now().Add(-5 * time.Minute)

	// Seed deleted message
	msg := &domain.Message{
		ID:        "msg-deleted-while-offline",
		RoomID:    "room-100",
		SenderID:  "user-alice",
		IsDeleted: true,
		DeletedAt: &deletedAt,
		CreatedAt: since.Add(-1 * time.Hour),
	}
	chatRepo.messages = append(chatRepo.messages, msg)

	// Bob reconnects and syncs deletions
	deletions, err := usecase.GetOfflineDeletions(context.Background(), "user-bob", since)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(deletions) != 1 || deletions[0] != "msg-deleted-while-offline" {
		t.Errorf("expected 1 deletion tombstone, got %v", deletions)
	}
}

