package domain

import (
	"time"
)

// Notification represents a push delivery alert message payload.
type Notification struct {
	ID          string            `json:"id"`
	RecipientID string            `json:"recipient_id"`
	Title       string            `json:"title"`
	Body        string            `json:"body"`
	Payload     map[string]string `json:"payload"`
	Status      string            `json:"status"` // PENDING, SENT, FAILED, RETRYING
	CreatedAt   time.Time         `json:"created_at"`
}

// NotificationPreference stores user push configurations and quiet hour restrictions.
type NotificationPreference struct {
	UserID          string `json:"user_id"`
	EnablePush      bool   `json:"enable_push"`
	QuietHoursStart string `json:"quiet_hours_start"` // Format: "HH:MM" (e.g. "22:00")
	QuietHoursEnd   string `json:"quiet_hours_end"`   // Format: "HH:MM" (e.g. "08:00")
}
