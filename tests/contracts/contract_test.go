package contracts

import (
	"bytes"
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

// UserContract represents the structural schema contract for the Auth Service registration responses.
type UserContract struct {
	ID        string    `json:"id"`
	Pseudonym string    `json:"pseudonym"`
	DeviceID  string    `json:"device_id"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// MediaContract represents the structural schema contract for the Media Service upload responses.
type MediaContract struct {
	FileID      string    `json:"file_id"`
	Name        string    `json:"name"`
	ContentType string    `json:"content_type"`
	Size        int64     `json:"size"`
	S3Key       string    `json:"s3_key"`
	OwnerID     string    `json:"owner_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// ValidateSchema verifies that the raw JSON payload matches the target contract struct.
func ValidateSchema(rawJSON []byte, target interface{}) error {
	// Attempt decoding
	var temp map[string]interface{}
	if err := json.Unmarshal(rawJSON, &temp); err != nil {
		return fmt.Errorf("JSON decoding failure: %w", err)
	}

	// Re-marshal to concrete struct to assert parameter integrity
	dec := json.NewDecoder(bytes.NewReader(rawJSON))
	dec.DisallowUnknownFields() // Reject unknown contract attributes!
	if err := dec.Decode(target); err != nil {
		return fmt.Errorf("contract validation failed: schema mismatch: %w", err)
	}
	return nil
}

func TestConsumerContract_AuthRegistration(t *testing.T) {
	// Simulated response payload from Auth Service Provider
	providerResponse := []byte(`{
		"id": "018f2a5c-3d6f-7000-8b0a-7b8c9d0e1f2a",
		"pseudonym": "user-018f2a5c",
		"device_id": "device_123",
		"role": "anonymous_user",
		"created_at": "2026-07-01T15:00:00Z",
		"updated_at": "2026-07-01T15:00:00Z"
	}`)

	var contract UserContract
	err := ValidateSchema(providerResponse, &contract)
	if err != nil {
		t.Fatalf("Consumer registration contract violation: %v", err)
	}

	if contract.ID != "018f2a5c-3d6f-7000-8b0a-7b8c9d0e1f2a" || contract.Pseudonym != "user-018f2a5c" {
		t.Errorf("expected values mismatch in contract fields")
	}
}

func TestConsumerContract_AuthRegistration_Violation(t *testing.T) {
	// Payload containing invalid/unknown fields (violating contract)
	invalidResponse := []byte(`{
		"id": "018f2a5c-3d6f-7000-8b0a-7b8c9d0e1f2a",
		"pseudonym": "user-018f2a5c",
		"device_id": "device_123",
		"role": "anonymous_user",
		"created_at": "2026-07-01T15:00:00Z",
		"updated_at": "2026-07-01T15:00:00Z",
		"deprecated_legacy_field": "some-value"
	}`)

	var contract UserContract
	err := ValidateSchema(invalidResponse, &contract)
	if err == nil {
		t.Error("expected contract validation to fail on unknown fields, but it passed")
	}
}

func TestConsumerContract_MediaUpload(t *testing.T) {
	providerResponse := []byte(`{
		"file_id": "file_11029",
		"name": "avatar.jpg",
		"content_type": "image/jpeg",
		"size": 1024,
		"s3_key": "media/user_1/file_11029",
		"owner_id": "user_1",
		"created_at": "2026-07-01T15:00:00Z"
	}`)

	var contract MediaContract
	err := ValidateSchema(providerResponse, &contract)
	if err != nil {
		t.Fatalf("Consumer media upload contract violation: %v", err)
	}
}
