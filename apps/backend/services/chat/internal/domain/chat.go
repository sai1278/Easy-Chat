package domain

import (
	"time"
)

// Message represents a direct text/media chat message payload.
type Message struct {
	ID               string    `json:"message_id"`
	RoomID           string    `json:"room_id"`
	SenderID         string    `json:"sender_id"`
	EncryptedPayload []byte    `json:"encrypted_payload"`
	IdempotencyKey   string    `json:"idempotency_key"`
	CreatedAt        time.Time `json:"created_at"`
}

// ReadReceipt tracks message delivery state and read acknowledgement.
type ReadReceipt struct {
	MessageID string    `json:"message_id"`
	RoomID    string    `json:"room_id"`
	UserID    string    `json:"user_id"`
	Status    string    `json:"status"` // "DELIVERED" or "READ"
	Timestamp time.Time `json:"timestamp"`
}

// TypingIndicator represents transient user typing actions.
type TypingIndicator struct {
	RoomID   string `json:"room_id"`
	UserID   string `json:"user_id"`
	IsTyping bool   `json:"is_typing"`
}

// EventPacket is the wrapper type dispatched/received over WebSocket connections.
type EventPacket struct {
	Type     string           `json:"type"` // "MESSAGE", "TYPING", "RECEIPT"
	SenderID string           `json:"sender_id"`
	RoomID   string           `json:"room_id"`
	Message  *Message         `json:"message,omitempty"`
	Typing   *TypingIndicator `json:"typing,omitempty"`
	Receipt  *ReadReceipt     `json:"receipt,omitempty"`
}
