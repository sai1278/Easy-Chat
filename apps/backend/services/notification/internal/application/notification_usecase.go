package application

import (
	"context"
	"errors"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"nearby/backend/services/notification/internal/domain"
)

var (
	ErrDeduplicated = errors.New("notification deduplicated, already processed")
	ErrPushDisabled = errors.New("user has disabled push notifications")
	ErrQuietHours   = errors.New("quiet hours active, delivery postponed")
	ErrThrottled    = errors.New("rate limit exceeded for recipient")
)

type NotificationUsecase struct {
	prefRepo  domain.PreferenceRepository
	queueRepo domain.QueueRepository
	pusher    domain.PushProvider
}

func NewNotificationUsecase(prefRepo domain.PreferenceRepository, queueRepo domain.QueueRepository, pusher domain.PushProvider) *NotificationUsecase {
	return &NotificationUsecase{
		prefRepo:  prefRepo,
		queueRepo: queueRepo,
		pusher:    pusher,
	}
}

// ProcessNotification orchestrates deduplication, quiet hours filtering, rate limiting, batching, and push dispatching.
func (u *NotificationUsecase) ProcessNotification(ctx context.Context, notif *domain.Notification) error {
	// 1. Deduplication Lock (Cache lock key for 24 hours)
	acquired, err := u.queueRepo.AcquireDeduplicationLock(ctx, notif.ID, 24*time.Hour)
	if err != nil {
		return err
	}
	if !acquired {
		return ErrDeduplicated
	}

	// 2. Fetch User preferences
	pref, err := u.prefRepo.GetPreference(ctx, notif.RecipientID)
	if err != nil {
		return err
	}

	if !pref.EnablePush {
		return ErrPushDisabled
	}

	// 3. Evaluate Quiet Hours boundaries
	inQuietHours := u.checkQuietHours(time.Now(), pref.QuietHoursStart, pref.QuietHoursEnd)
	if inQuietHours {
		// Queue for retry delivery after quiet hours end (e.g. mock delay queue)
		_ = u.queueRepo.QueueRetry(ctx, notif, 1*time.Hour)
		return ErrQuietHours
	}

	// 4. Throttling Rate Limiter Check (Max 5 push notifications per 1 minute)
	throttled, err := u.queueRepo.RateLimitExceeded(ctx, notif.RecipientID, 5, 1*time.Minute)
	if err != nil {
		return err
	}
	if throttled {
		return ErrThrottled
	}

	// 5. Notification Batching consolidation check
	flush, err := u.queueRepo.BatchNotification(ctx, notif.RecipientID, notif)
	if err != nil {
		return err
	}
	if !flush {
		// Notification has been buffered into the batch. Do not send individually.
		return nil
	}

	// 6. Push Delivery Dispatch
	err = u.pusher.SendPush(ctx, notif)
	if err != nil {
		slog.Warn("Failed to send push notification, queuing retry", "id", notif.ID, "err", err)
		// Retry with 10 seconds backoff delay
		_ = u.queueRepo.QueueRetry(ctx, notif, 10*time.Second)
		return err
	}

	return nil
}

func (u *NotificationUsecase) checkQuietHours(t time.Time, startStr, endStr string) bool {
	if startStr == "" || endStr == "" {
		return false
	}

	startMin := parseTimeMinutes(startStr)
	endMin := parseTimeMinutes(endStr)
	nowMin := t.Hour()*60 + t.Minute()

	if startMin == endMin {
		return false
	}

	if startMin < endMin {
		// Case: Quiet hours within same day (e.g., 09:00 to 17:00)
		return nowMin >= startMin && nowMin <= endMin
	} else {
		// Case: Quiet hours crossing midnight (e.g., 22:00 to 08:00)
		return nowMin >= startMin || nowMin <= endMin
	}
}

func parseTimeMinutes(timeStr string) int {
	parts := strings.Split(timeStr, ":")
	if len(parts) != 2 {
		return 0
	}
	hours, _ := strconv.Atoi(parts[0])
	mins, _ := strconv.Atoi(parts[1])
	return hours*60 + mins
}
