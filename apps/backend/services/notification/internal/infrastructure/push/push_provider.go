package push

import (
	"context"
	"errors"
	"log/slog"
	"math/rand"
	"time"

	"nearby/backend/services/notification/internal/domain"
)

// PushProviderAdapter implements domain.PushProvider.
type PushProviderAdapter struct {
	// Credentials / FCM client parameters go here
	simulateFailure bool
}

// NewPushProviderAdapter creates a new PushProviderAdapter.
func NewPushProviderAdapter(simulateFailure bool) *PushProviderAdapter {
	return &PushProviderAdapter{simulateFailure: simulateFailure}
}

// SendPush simulates push notification dispatching to FCM/APNs.
func (p *PushProviderAdapter) SendPush(ctx context.Context, push *domain.Notification) error {
	slog.Info("Dispatching push alert frame", 
		"id", push.ID, 
		"recipient", push.RecipientID, 
		"title", push.Title, 
		"body", push.Body,
	)

	// Simulate network roundtrip latency
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(10 * time.Millisecond):
	}

	if p.simulateFailure {
		return errors.New("temporary push provider network error")
	}

	// 5% random failure rate in real simulated scenarios
	if rand.Float32() < 0.05 {
		return errors.New("upstream gateway timeout")
	}

	slog.Info("Push alert successfully delivered", "id", push.ID)
	push.Status = "SENT"
	return nil
}
