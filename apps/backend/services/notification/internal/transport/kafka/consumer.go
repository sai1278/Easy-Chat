package kafka

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/segmentio/kafka-go"
	"nearby/backend/services/notification/internal/application"
	"nearby/backend/services/notification/internal/domain"
)

type NotificationConsumer struct {
	reader  *kafka.Reader
	usecase *application.NotificationUsecase
}

func NewNotificationConsumer(brokers []string, topic string, groupID string, usecase *application.NotificationUsecase) *NotificationConsumer {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       10e3, // 10KB
		MaxBytes:       10e6, // 10MB
		CommitInterval: time.Second,
	})

	return &NotificationConsumer{
		reader:  reader,
		usecase: usecase,
	}
}

// Start listens to Kafka message loops until context is canceled.
func (c *NotificationConsumer) Start(ctx context.Context) {
	slog.Info("Kafka Notification Consumer started listening to events")
	for {
		msg, err := c.reader.ReadMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			slog.Error("Kafka consumer read message error", "err", err)
			time.Sleep(2 * time.Second) // wait before retry
			continue
		}

		var notif domain.Notification
		if err := json.Unmarshal(msg.Value, &notif); err != nil {
			slog.Error("Failed to unmarshal notification event", "err", err)
			continue
		}

		// Process consumed event
		err = c.usecase.ProcessNotification(ctx, &notif)
		if err != nil {
			if err == application.ErrDeduplicated {
				slog.Debug("Notification skipped: deduplicated", "id", notif.ID)
			} else if err == application.ErrQuietHours {
				slog.Info("Notification deferred: quiet hours active", "id", notif.ID, "user", notif.RecipientID)
			} else {
				slog.Warn("Notification process completed with warnings/retries", "id", notif.ID, "err", err)
			}
		} else {
			slog.Info("Notification successfully processed from Kafka stream", "id", notif.ID)
		}
	}
}

func (c *NotificationConsumer) Close() error {
	return c.reader.Close()
}
