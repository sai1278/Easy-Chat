package domain

import (
	"time"
)

// FileMetadata represents a stored media attachment record.
type FileMetadata struct {
	ID          string    `json:"file_id"`
	Name        string    `json:"name"`
	ContentType string    `json:"content_type"`
	Size        int64     `json:"size"`
	S3Key       string    `json:"s3_key"`
	OwnerID     string    `json:"owner_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// PreSignedUrlResponse wraps the generated pre-signed upload or download endpoint URL.
type PreSignedUrlResponse struct {
	URL     string    `json:"url"`
	Expiry  time.Time `json:"expiry"`
	FileID  string    `json:"file_id"`
	Headers map[string]string `json:"headers,omitempty"`
}
