package domain

import (
	"encoding/json"
	"time"
)

// ChatRequestStatus represents the state lifecycle of a direct chat request.
type ChatRequestStatus string

const (
	RequestStatusPending   ChatRequestStatus = "PENDING"
	RequestStatusAccepted  ChatRequestStatus = "ACCEPTED"
	RequestStatusDenied    ChatRequestStatus = "DENIED"
	RequestStatusCancelled ChatRequestStatus = "CANCELLED"
)

// ChatRequest represents a formal invitation between two users before messaging is permitted.
type ChatRequest struct {
	ID                string            `json:"id"`
	SenderID          string            `json:"sender_id"`
	RecipientID       string            `json:"recipient_id"`
	RoomID            string            `json:"room_id,omitempty"`
	Status            ChatRequestStatus `json:"status"`
	CreatedAt         time.Time         `json:"created_at"`
	UpdatedAt         time.Time         `json:"updated_at"`
	RespondedAt       *time.Time        `json:"responded_at,omitempty"`
	SenderDisplayName string            `json:"sender_display_name,omitempty"`
	SenderUsername    string            `json:"sender_username,omitempty"`
	SenderAvatarURL   string            `json:"sender_avatar_url,omitempty"`
	SenderBio         string            `json:"sender_bio,omitempty"`
}

// Message represents a direct text/media chat message payload.
type Message struct {
	ID               string     `json:"message_id"`
	RoomID           string     `json:"room_id"`
	SenderID         string     `json:"sender_id"`
	EncryptedPayload []byte     `json:"encrypted_payload"`
	IdempotencyKey   string     `json:"idempotency_key"`
	IsDeleted        bool       `json:"is_deleted,omitempty"`
	DeletedAt        *time.Time `json:"deleted_at,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// UnmarshalJSON provides flexible timestamp parsing for incoming client messages.
func (m *Message) UnmarshalJSON(data []byte) error {
	type Alias Message
	aux := &struct {
		CreatedAtRaw json.RawMessage `json:"created_at"`
		*Alias
	}{
		Alias: (*Alias)(m),
	}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	if len(aux.CreatedAtRaw) > 0 {
		var s string
		if err := json.Unmarshal(aux.CreatedAtRaw, &s); err == nil && s != "" {
			t, err := time.Parse(time.RFC3339Nano, s)
			if err != nil {
				t, err = time.Parse("2006-01-02T15:04:05.999999999", s)
			}
			if err != nil {
				t, err = time.Parse("2006-01-02T15:04:05", s)
			}
			if err == nil {
				m.CreatedAt = t
			} else {
				m.CreatedAt = time.Now().UTC()
			}
		} else {
			m.CreatedAt = time.Now().UTC()
		}
	} else {
		m.CreatedAt = time.Now().UTC()
	}
	return nil
}

// DeleteMessageRequest represents an incoming client deletion command.
type DeleteMessageRequest struct {
	MessageID  string `json:"message_id"`
	RoomID     string `json:"room_id"`
	DeleteType string `json:"delete_type"` // "FOR_EVERYONE" or "FOR_ME"
}

// DeleteMessageEvent represents a deletion tombstone broadcast.
type DeleteMessageEvent struct {
	MessageID string `json:"message_id"`
	RoomID    string `json:"room_id"`
}

// UserCryptoIdentity represents public keys registered for E2EE session agreement.
type UserCryptoIdentity struct {
	UserID          string    `json:"user_id"`
	IdentityKeyPub  string    `json:"identity_key_pub"`
	SignedPrekeyPub string    `json:"signed_prekey_pub"`
	SignedPrekeySig string    `json:"signed_prekey_sig"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// ReadReceipt tracks message delivery state and read acknowledgement.
type ReadReceipt struct {
	MessageID string    `json:"message_id"`
	RoomID    string    `json:"room_id"`
	UserID    string    `json:"user_id"`
	Status    string    `json:"status"` // "DELIVERED" or "READ"
	Timestamp time.Time `json:"timestamp"`
}

// UnmarshalJSON provides flexible timestamp parsing for incoming read receipts.
func (r *ReadReceipt) UnmarshalJSON(data []byte) error {
	type Alias ReadReceipt
	aux := &struct {
		TimestampRaw json.RawMessage `json:"timestamp"`
		*Alias
	}{
		Alias: (*Alias)(r),
	}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	if len(aux.TimestampRaw) > 0 {
		var s string
		if err := json.Unmarshal(aux.TimestampRaw, &s); err == nil && s != "" {
			t, err := time.Parse(time.RFC3339Nano, s)
			if err != nil {
				t, err = time.Parse("2006-01-02T15:04:05.999999999", s)
			}
			if err != nil {
				t, err = time.Parse("2006-01-02T15:04:05", s)
			}
			if err == nil {
				r.Timestamp = t
			} else {
				r.Timestamp = time.Now().UTC()
			}
		} else {
			r.Timestamp = time.Now().UTC()
		}
	} else {
		r.Timestamp = time.Now().UTC()
	}
	return nil
}

// TypingIndicator represents transient user typing actions.
type TypingIndicator struct {
	RoomID   string `json:"room_id"`
	UserID   string `json:"user_id"`
	IsTyping bool   `json:"is_typing"`
}

// EventPacket is the wrapper type dispatched/received over WebSocket connections.
type EventPacket struct {
	Type          string              `json:"type"` // "MESSAGE", "DELETE_MESSAGE", "MESSAGE_DELETED", "TYPING", "RECEIPT", "CHAT_REQUEST_RECEIVED", "CHAT_REQUEST_ACCEPTED", "CHAT_REQUEST_DENIED"
	SenderID      string              `json:"sender_id"`
	RoomID        string              `json:"room_id,omitempty"`
	Message       *Message            `json:"message,omitempty"`
	DeleteMessage *DeleteMessageEvent `json:"delete_message,omitempty"`
	Typing        *TypingIndicator    `json:"typing,omitempty"`
	Receipt       *ReadReceipt        `json:"receipt,omitempty"`
	ChatRequest   *ChatRequest        `json:"chat_request,omitempty"`
}

