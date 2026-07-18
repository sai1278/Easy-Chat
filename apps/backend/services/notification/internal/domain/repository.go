package domain

import (
	"context"
	"time"
)

// PreferenceRepository handles storing and loading push notification settings.
type PreferenceRepository interface {
	SavePreference(ctx context.Context, pref *NotificationPreference) error
	GetPreference(ctx context.Context, userID string) (*NotificationPreference, error)
}

// PushProvider handles dispatching notification frames to FCM or APNs.
type PushProvider interface {
	SendPush(ctx context.Context, push *Notification) error
}

// QueueRepository abstracts Redis interactions for deduplication, throttling, retries, and batching.
type QueueRepository interface {
	AcquireDeduplicationLock(ctx context.Context, notificationID string, ttl time.Duration) (bool, error)
	RateLimitExceeded(ctx context.Context, userID string, limit int, window time.Duration) (bool, error)
	QueueRetry(ctx context.Context, push *Notification, delay time.Duration) error
	BatchNotification(ctx context.Context, userID string, push *Notification) (bool, error)
}
