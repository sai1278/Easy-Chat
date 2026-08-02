package application

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"nearby/backend/services/notification/internal/domain"
)

// MockPreferenceRepository implements domain.PreferenceRepository.
type MockPreferenceRepository struct {
	mu    sync.RWMutex
	cache map[string]*domain.NotificationPreference
}

func (m *MockPreferenceRepository) SavePreference(ctx context.Context, pref *domain.NotificationPreference) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cache == nil {
		m.cache = make(map[string]*domain.NotificationPreference)
	}
	m.cache[pref.UserID] = pref
	return nil
}

func (m *MockPreferenceRepository) GetPreference(ctx context.Context, userID string) (*domain.NotificationPreference, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	pref, exists := m.cache[userID]
	if !exists {
		return &domain.NotificationPreference{
			UserID:          userID,
			EnablePush:      true,
			QuietHoursStart: "22:00",
			QuietHoursEnd:   "08:00",
		}, nil
	}
	return pref, nil
}

// MockQueueRepository implements domain.QueueRepository.
type MockQueueRepository struct {
	mu        sync.RWMutex
	dupCache  map[string]time.Time
	throttle  map[string][]time.Time
	batches   map[string][]*domain.Notification
	retryList []*domain.Notification
}

func (m *MockQueueRepository) AcquireDeduplicationLock(ctx context.Context, notificationID string, ttl time.Duration) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.dupCache == nil {
		m.dupCache = make(map[string]time.Time)
	}
	if _, exists := m.dupCache[notificationID]; exists {
		return false, nil
	}
	m.dupCache[notificationID] = time.Now().Add(ttl)
	return true, nil
}

func (m *MockQueueRepository) RateLimitExceeded(ctx context.Context, userID string, limit int, window time.Duration) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.throttle == nil {
		m.throttle = make(map[string][]time.Time)
	}
	list := m.throttle[userID]
	now := time.Now()
	var active []time.Time
	cutoff := now.Add(-window)
	for _, t := range list {
		if t.After(cutoff) {
			active = append(active, t)
		}
	}
	if len(active) >= limit {
		return true, nil
	}
	active = append(active, now)
	m.throttle[userID] = active
	return false, nil
}

func (m *MockQueueRepository) QueueRetry(ctx context.Context, push *domain.Notification, delay time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.retryList = append(m.retryList, push)
	return nil
}

func (m *MockQueueRepository) BatchNotification(ctx context.Context, userID string, push *domain.Notification) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.batches == nil {
		m.batches = make(map[string][]*domain.Notification)
	}
	list := m.batches[userID]
	list = append(list, push)
	m.batches[userID] = list

	if len(list) >= 3 {
		m.batches[userID] = nil // Reset batch
		return true, nil
	}
	return false, nil
}

// MockPushProvider implements domain.PushProvider.
type MockPushProvider struct {
	mu   sync.Mutex
	sent []*domain.Notification
}

func (m *MockPushProvider) SendPush(ctx context.Context, push *domain.Notification) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sent = append(m.sent, push)
	return nil
}

// fixedActiveTime represents 14:00 UTC (outside quiet hours 22:00-08:00)
var fixedActiveTime = MockClock{Time: time.Date(2026, 8, 2, 14, 0, 0, 0, time.UTC)}

// fixedQuietTime represents 23:30 UTC (inside quiet hours 22:00-08:00)
var fixedQuietTime = MockClock{Time: time.Date(2026, 8, 2, 23, 30, 0, 0, time.UTC)}

func TestNotificationUsecase_ProcessNotification_Deduplication(t *testing.T) {
	prefRepo := &MockPreferenceRepository{}
	queueRepo := &MockQueueRepository{}
	pusher := &MockPushProvider{}
	usecase := NewNotificationUsecase(prefRepo, queueRepo, pusher, fixedActiveTime)

	notif := &domain.Notification{
		ID:          "notif_1",
		RecipientID: "user_1",
		Title:       "Title",
		Body:        "Body",
	}

	// 1. First send: Should batch (not flushed yet, returns nil)
	err := usecase.ProcessNotification(context.Background(), notif)
	if err != nil {
		t.Fatalf("unexpected first send error: %v", err)
	}

	// 2. Second send with same ID: Should return ErrDeduplicated immediately
	err = usecase.ProcessNotification(context.Background(), notif)
	if err != ErrDeduplicated {
		t.Errorf("expected ErrDeduplicated, got %v", err)
	}
}

func TestNotificationUsecase_ProcessNotification_QuietHours_Active(t *testing.T) {
	prefRepo := &MockPreferenceRepository{}
	queueRepo := &MockQueueRepository{}
	pusher := &MockPushProvider{}

	// Inject clock set to 23:30 (inside quiet hours 22:00 to 08:00)
	usecase := NewNotificationUsecase(prefRepo, queueRepo, pusher, fixedQuietTime)

	notif := &domain.Notification{
		ID:          "notif_quiet_1",
		RecipientID: "user_quiet",
		Title:       "Quiet Title",
		Body:        "Quiet Body",
	}

	err := usecase.ProcessNotification(context.Background(), notif)
	if err != ErrQuietHours {
		t.Fatalf("expected ErrQuietHours during active quiet hours, got: %v", err)
	}

	if len(queueRepo.retryList) != 1 {
		t.Errorf("expected 1 notification queued for retry, got %d", len(queueRepo.retryList))
	}
}

func TestNotificationUsecase_ProcessNotification_QuietHours_Inactive(t *testing.T) {
	prefRepo := &MockPreferenceRepository{}
	queueRepo := &MockQueueRepository{}
	pusher := &MockPushProvider{}

	// Inject clock set to 14:00 (outside quiet hours)
	usecase := NewNotificationUsecase(prefRepo, queueRepo, pusher, fixedActiveTime)

	notif := &domain.Notification{
		ID:          "notif_active_1",
		RecipientID: "user_active",
		Title:       "Active Title",
		Body:        "Active Body",
	}

	err := usecase.ProcessNotification(context.Background(), notif)
	if err != nil {
		t.Fatalf("expected no error outside quiet hours, got: %v", err)
	}
}

func TestNotificationUsecase_ProcessNotification_Throttling(t *testing.T) {
	prefRepo := &MockPreferenceRepository{}
	queueRepo := &MockQueueRepository{}
	pusher := &MockPushProvider{}
	usecase := NewNotificationUsecase(prefRepo, queueRepo, pusher, fixedActiveTime)

	// Send 6 separate notifications (limit is 5)
	for i := 1; i <= 6; i++ {
		notif := &domain.Notification{
			ID:          fmt.Sprintf("notif_%d", i),
			RecipientID: "user_3",
			Title:       "Title",
			Body:        "Body",
		}
		err := usecase.ProcessNotification(context.Background(), notif)
		if i <= 5 {
			if err != nil {
				t.Fatalf("unexpected error at sending %d: %v", i, err)
			}
		} else {
			if err != ErrThrottled {
				t.Errorf("expected ErrThrottled at 6th send, got %v", err)
			}
		}
	}
}

func TestNotificationUsecase_ProcessNotification_Batching(t *testing.T) {
	prefRepo := &MockPreferenceRepository{}
	queueRepo := &MockQueueRepository{}
	pusher := &MockPushProvider{}
	usecase := NewNotificationUsecase(prefRepo, queueRepo, pusher, fixedActiveTime)

	// Batch is set to flush at size 3
	for i := 1; i <= 3; i++ {
		notif := &domain.Notification{
			ID:          fmt.Sprintf("notif_%d", i),
			RecipientID: "user_4",
			Title:       "Title",
			Body:        "Body",
		}
		err := usecase.ProcessNotification(context.Background(), notif)
		if err != nil {
			t.Fatalf("unexpected send error on item %d: %v", i, err)
		}

		if i < 3 {
			// Should not have dispatched yet
			if len(pusher.sent) > 0 {
				t.Errorf("expected push queue to remain idle, but got size %d", len(pusher.sent))
			}
		} else {
			// 3rd notification must trigger flush
			if len(pusher.sent) != 1 {
				t.Errorf("expected push queue to flush batch summary, but got size %d", len(pusher.sent))
			}
		}
	}
}
