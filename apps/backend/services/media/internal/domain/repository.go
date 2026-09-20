package domain

import (
	"context"
	"time"
)

// MetadataRepository handles persisting and fetching file attachment records.
type MetadataRepository interface {
	SaveMetadata(ctx context.Context, meta *FileMetadata) error
	GetMetadata(ctx context.Context, id string) (*FileMetadata, error)
	DeleteMetadata(ctx context.Context, id string) error
	IsUserInRoom(ctx context.Context, userID, roomID string) (bool, error)
	IsMessageActiveInRoom(ctx context.Context, messageID, roomID string) (bool, error)
}

// StorageRepository abstracts S3-compatible cloud storage operations and presigned URL creation.
type StorageRepository interface {
	UploadFile(ctx context.Context, key string, data []byte, contentType string) error
	DownloadFile(ctx context.Context, key string) ([]byte, error)
	DeleteFile(ctx context.Context, key string) error
	GeneratePreSignedUploadURL(ctx context.Context, key string, expiry time.Duration) (string, error)
	GeneratePreSignedDownloadURL(ctx context.Context, key string, expiry time.Duration) (string, error)
}

// ScannerPipeline scans content payload streams for known malware and viruses.
type ScannerPipeline interface {
	Scan(ctx context.Context, data []byte) (bool, error)
}
