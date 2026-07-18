package tests

import (
	"context"
	"sync"
	"testing"
	"time"

	"nearby/backend/internal/pkg/idempotency"
)

// MockStore implements the idempotency.Store interface in-memory.
type MockStore struct {
	mu    sync.Mutex
	data  map[string]string
	ttls  map[string]time.Time
}

func NewMockStore() *MockStore {
	return &MockStore{
		data: make(map[string]string),
		ttls: make(map[string]time.Time),
	}
}

func (m *MockStore) Get(ctx context.Context, key string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	expiry, exists := m.ttls[key]
	if exists && time.Now().After(expiry) {
		delete(m.data, key)
		delete(m.ttls, key)
		return "", nil
	}

	return m.data[key], nil
}

func (m *MockStore) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.data[key] = value
	m.ttls[key] = time.Now().Add(ttl)
	return nil
}

func (m *MockStore) SetNX(ctx context.Context, key string, value string, ttl time.Duration) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Check expiry
	expiry, exists := m.ttls[key]
	if exists && time.Now().After(expiry) {
		delete(m.data, key)
		delete(m.ttls, key)
	} else if exists {
		return false, nil // Key exists and has not expired
	}

	m.data[key] = value
	m.ttls[key] = time.Now().Add(ttl)
	return true, nil
}

func (m *MockStore) Del(ctx context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	delete(m.data, key)
	delete(m.ttls, key)
	return nil
}

func TestIdempotencyAcquireCommit(t *testing.T) {
	store := NewMockStore()
	engine := idempotency.NewEngine(store, 1*time.Hour)
	ctx := context.Background()

	key := "test-request-key-1"

	// 1. First attempt should succeed (acquire lock)
	cached, exists, err := engine.Acquire(ctx, key)
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
	if exists {
		t.Fatalf("Expected exists to be false on first call")
	}
	if cached != nil {
		t.Fatalf("Expected cached response to be nil")
	}

	// 2. Immediate second attempt should conflict (request in progress)
	_, _, err = engine.Acquire(ctx, key)
	if err != idempotency.ErrRequestInProgress {
		t.Fatalf("Expected ErrRequestInProgress, got: %v", err)
	}

	// 3. Commit response
	bodyPayload := []byte(`{"status":"success"}`)
	headers := map[string]string{"Content-Type": "application/json"}
	err = engine.Commit(ctx, key, 201, bodyPayload, headers)
	if err != nil {
		t.Fatalf("Failed to commit response: %v", err)
	}

	// 4. Subsequent attempt should hit cache
	cached, exists, err = engine.Acquire(ctx, key)
	if err != nil {
		t.Fatalf("Expected no error on cached check, got: %v", err)
	}
	if !exists {
		t.Fatalf("Expected exists to be true for cached check")
	}
	if cached == nil {
		t.Fatalf("Expected cached response to be populated")
	}
	if cached.Status != 201 {
		t.Errorf("Expected status 201, got: %d", cached.Status)
	}
}
