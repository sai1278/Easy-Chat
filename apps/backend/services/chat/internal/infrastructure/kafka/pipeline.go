package kafka

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	kafka "github.com/segmentio/kafka-go"
	_ "github.com/segmentio/kafka-go/snappy"
	"nearby/backend/services/chat/internal/domain"
)

// KafkaPipeline implements domain.EventPipeline using segmentio/kafka-go.
type KafkaPipeline struct {
	writer    *kafka.Writer
	reader    *kafka.Reader
	dlqWriter *kafka.Writer // writes undeserializable messages to the dead-letter topic
}

// NewKafkaPipeline creates a new KafkaPipeline.
// dlqTopic is the dead-letter topic for undeserializable messages. Pass an empty
// string to disable DLQ publishing (not recommended for production).
func NewKafkaPipeline(brokers []string, topic string, groupID string, dlqTopic string) *KafkaPipeline {
	writer := &kafka.Writer{
		Addr:         kafka.TCP(brokers...),
		Topic:        topic,
		Balancer:     &kafka.Hash{},          // Partition by room_id for strict ordering
		Compression:  kafka.Snappy,           // Snappy compression — low CPU, high throughput
		BatchSize:    500,
		BatchTimeout: 10 * time.Millisecond,
		MaxAttempts:  5,
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  brokers,
		GroupID:  groupID,
		Topic:    topic,
		MinBytes: 1,
		MaxBytes: 10e6,
		MaxWait:  10 * time.Millisecond,
	})

	var dlqWriter *kafka.Writer
	if dlqTopic != "" {
		dlqWriter = &kafka.Writer{
			Addr:        kafka.TCP(brokers...),
			Topic:       dlqTopic,
			Balancer:    &kafka.Hash{},
			MaxAttempts: 3,
		}
	}

	return &KafkaPipeline{
		writer:    writer,
		reader:    reader,
		dlqWriter: dlqWriter,
	}
}

// PublishChatEvent sends a chat packet to Kafka.
func (p *KafkaPipeline) PublishChatEvent(ctx context.Context, event *domain.EventPacket) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return err
	}

	return p.writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(event.RoomID),
		Value: payload,
	})
}

// ConsumeChatEvents reads events from Kafka and broadcasts them down a Go channel.
// HIGH-13: Deserialization failures are now logged and published to a dead-letter topic
// instead of being silently discarded.
func (p *KafkaPipeline) ConsumeChatEvents(ctx context.Context) (<-chan *domain.EventPacket, error) {
	ch := make(chan *domain.EventPacket, 100)

	go func() {
		defer close(ch)
		for {
			m, err := p.reader.ReadMessage(ctx)
			if err != nil {
				if ctx.Err() != nil {
					// Stop loop on context cancellation.
					return
				}
				slog.Error("Kafka consumer ReadMessage error, retrying", "err", err)
				time.Sleep(500 * time.Millisecond)
				continue
			}

			var event domain.EventPacket
			if err := json.Unmarshal(m.Value, &event); err != nil {
				// HIGH-13: Log the deserialization failure with full context.
				// The message is published to the DLQ writer so it can be
				// investigated and replayed without data loss.
				slog.Error("Kafka deserialization error",
					"topic", m.Topic,
					"partition", m.Partition,
					"offset", m.Offset,
					"raw_bytes", len(m.Value),
					"err", err,
				)
				if p.dlqWriter != nil {
					_ = p.dlqWriter.WriteMessages(ctx, kafka.Message{
						Key:   m.Key,
						Value: m.Value,
						Headers: []kafka.Header{
							{Key: "dlq-reason", Value: []byte(err.Error())},
							{Key: "dlq-original-topic", Value: []byte(m.Topic)},
						},
					})
				}
				continue
			}

			select {
			case ch <- &event:
			case <-ctx.Done():
				return
			}
		}
	}()

	return ch, nil
}

// Close releases writer, reader, and DLQ writer resources.
func (p *KafkaPipeline) Close() error {
	var err1, err2, err3 error
	if p.writer != nil {
		err1 = p.writer.Close()
	}
	if p.reader != nil {
		err2 = p.reader.Close()
	}
	if p.dlqWriter != nil {
		err3 = p.dlqWriter.Close()
	}
	for _, e := range []error{err1, err2, err3} {
		if e != nil {
			return e
		}
	}
	return nil
}
