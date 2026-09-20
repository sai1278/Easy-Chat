package application

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // register PNG decoder
	"time"

	"github.com/google/uuid"
	"nearby/backend/services/media/internal/domain"
)

var (
	ErrFileTooLarge          = errors.New("file size exceeds maximum limit of 10MB")
	ErrInvalidType           = errors.New("file type not allowed")
	ErrVirusDetected         = errors.New("malware signature detected, upload blocked")
	ErrUnauthorized          = errors.New("unauthorized: authentication required")
	ErrAccessDenied          = errors.New("access to this media resource is denied")
	ErrFileNotFound          = errors.New("file not found or deleted")
	ErrCrossRoomAccessDenied = errors.New("cross-room media access forbidden")
	ErrMessageDeleted        = errors.New("referenced message has been deleted")
	ErrMessageNotFound       = errors.New("referenced message not found in room")
)

type MediaUsecase struct {
	metaRepo  domain.MetadataRepository
	storeRepo domain.StorageRepository
	scanner   domain.ScannerPipeline
}

func NewMediaUsecase(metaRepo domain.MetadataRepository, storeRepo domain.StorageRepository, scanner domain.ScannerPipeline) *MediaUsecase {
	return &MediaUsecase{
		metaRepo:  metaRepo,
		storeRepo: storeRepo,
		scanner:   scanner,
	}
}

// ProcessUpload runs file validations, virus scans, compresses images, and stores the resource.
// If roomID is provided, verifies room membership before accepting upload.
func (u *MediaUsecase) ProcessUpload(ctx context.Context, ownerID, name, contentType, roomID, messageID string, data []byte) (*domain.FileMetadata, error) {
	if ownerID == "" {
		return nil, ErrUnauthorized
	}

	// 1. Enforce File Size Limit (10MB)
	if int64(len(data)) > 10*1024*1024 {
		return nil, ErrFileTooLarge
	}

	// 2. Scan for viruses
	clean, err := u.scanner.Scan(ctx, data)
	if err != nil {
		return nil, err
	}
	if !clean {
		return nil, ErrVirusDetected
	}

	// 3. If roomID is provided, verify caller is an active participant in that room
	if roomID != "" {
		inRoom, err := u.metaRepo.IsUserInRoom(ctx, ownerID, roomID)
		if err != nil {
			return nil, fmt.Errorf("failed to verify room membership: %w", err)
		}
		if !inRoom {
			return nil, ErrAccessDenied
		}
	}

	// 4. Compress Images if applicable (JPEG/PNG)
	if contentType == "image/jpeg" || contentType == "image/png" {
		img, _, err := image.Decode(bytes.NewReader(data))
		if err == nil {
			// Compress image to JPEG at 75% quality
			var buf bytes.Buffer
			err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 75})
			if err == nil {
				data = buf.Bytes()
				contentType = "image/jpeg" // Normalise to JPEG
			}
		}
	}

	// 5. Generate metadata and keys
	fileID := uuid.New().String()
	s3Key := fmt.Sprintf("media/%s/%s", ownerID, fileID)

	// 6. Upload to Cloud Storage
	if err := u.storeRepo.UploadFile(ctx, s3Key, data, contentType); err != nil {
		return nil, err
	}

	meta := &domain.FileMetadata{
		ID:          fileID,
		Name:        name,
		ContentType: contentType,
		Size:        int64(len(data)),
		S3Key:       s3Key,
		OwnerID:     ownerID,
		RoomID:      roomID,
		MessageID:   messageID,
		CreatedAt:   time.Now(),
	}

	// 7. Save metadata to PostgreSQL
	if err := u.metaRepo.SaveMetadata(ctx, meta); err != nil {
		return nil, err
	}

	return meta, nil
}

// AuthorizeMediaAccess enforces zero-trust backend authorization before any download, streaming, or presigned URL issue.
func (u *MediaUsecase) AuthorizeMediaAccess(ctx context.Context, userID, fileID, reqRoomID, reqMessageID string) (*domain.FileMetadata, error) {
	// 1. Authentication check
	if userID == "" {
		return nil, ErrUnauthorized
	}

	// 2. Fetch metadata record
	meta, err := u.metaRepo.GetMetadata(ctx, fileID)
	if err != nil {
		return nil, ErrFileNotFound
	}
	if meta.IsDeleted {
		return nil, ErrFileNotFound
	}

	// 3. Resolve and verify Room ID
	effectiveRoomID := meta.RoomID
	if effectiveRoomID != "" {
		// Prevent cross-room parameter tampering
		if reqRoomID != "" && reqRoomID != effectiveRoomID {
			return nil, ErrCrossRoomAccessDenied
		}
	} else if reqRoomID != "" {
		effectiveRoomID = reqRoomID
	}

	if effectiveRoomID != "" {
		// 4. Verify requesting user is an active participant in this room
		inRoom, err := u.metaRepo.IsUserInRoom(ctx, userID, effectiveRoomID)
		if err != nil {
			return nil, fmt.Errorf("failed to verify room membership: %w", err)
		}
		if !inRoom {
			return nil, ErrAccessDenied
		}
	} else {
		// Direct attachment without room: only owner or admin allowed
		if meta.OwnerID != userID && userID != "admin" {
			return nil, ErrAccessDenied
		}
	}

	// 5. Resolve and verify Message ID & Deletion State
	effectiveMessageID := meta.MessageID
	if effectiveMessageID != "" {
		if reqMessageID != "" && reqMessageID != effectiveMessageID {
			return nil, ErrMessageNotFound
		}
	} else if reqMessageID != "" {
		effectiveMessageID = reqMessageID
	}

	if effectiveMessageID != "" && effectiveRoomID != "" {
		active, err := u.metaRepo.IsMessageActiveInRoom(ctx, effectiveMessageID, effectiveRoomID)
		if err != nil {
			return nil, ErrMessageNotFound
		}
		if !active {
			return nil, ErrMessageDeleted
		}
	}

	return meta, nil
}

// GetSignedDownloadURL generates a pre-signed S3 download URL after checking zero-trust access control.
func (u *MediaUsecase) GetSignedDownloadURL(ctx context.Context, userID, fileID, reqRoomID, reqMessageID string, expiry time.Duration) (*domain.PreSignedUrlResponse, error) {
	meta, err := u.AuthorizeMediaAccess(ctx, userID, fileID, reqRoomID, reqMessageID)
	if err != nil {
		return nil, err
	}

	url, err := u.storeRepo.GeneratePreSignedDownloadURL(ctx, meta.S3Key, expiry)
	if err != nil {
		return nil, err
	}

	return &domain.PreSignedUrlResponse{
		URL:    url,
		Expiry: time.Now().Add(expiry),
		FileID: fileID,
	}, nil
}

// GetSignedUploadURL generates a pre-signed S3 upload URL.
func (u *MediaUsecase) GetSignedUploadURL(ctx context.Context, ownerID, name, roomID, messageID string, expiry time.Duration) (*domain.PreSignedUrlResponse, error) {
	if ownerID == "" {
		return nil, ErrUnauthorized
	}
	if roomID != "" {
		inRoom, err := u.metaRepo.IsUserInRoom(ctx, ownerID, roomID)
		if err != nil {
			return nil, fmt.Errorf("failed to verify room membership: %w", err)
		}
		if !inRoom {
			return nil, ErrAccessDenied
		}
	}

	fileID := uuid.New().String()
	s3Key := fmt.Sprintf("media/%s/%s", ownerID, fileID)

	url, err := u.storeRepo.GeneratePreSignedUploadURL(ctx, s3Key, expiry)
	if err != nil {
		return nil, err
	}

	meta := &domain.FileMetadata{
		ID:          fileID,
		Name:        name,
		ContentType: "application/octet-stream",
		Size:        0,
		S3Key:       s3Key,
		OwnerID:     ownerID,
		RoomID:      roomID,
		MessageID:   messageID,
		CreatedAt:   time.Now(),
	}
	_ = u.metaRepo.SaveMetadata(ctx, meta)

	return &domain.PreSignedUrlResponse{
		URL:    url,
		Expiry: time.Now().Add(expiry),
		FileID: fileID,
	}, nil
}

// GetFileBytes directly fetches the file bytes from storage for local/direct delivery after access authorization.
func (u *MediaUsecase) GetFileBytes(ctx context.Context, userID, fileID, reqRoomID, reqMessageID string) (*domain.FileMetadata, []byte, error) {
	meta, err := u.AuthorizeMediaAccess(ctx, userID, fileID, reqRoomID, reqMessageID)
	if err != nil {
		return nil, nil, err
	}

	data, err := u.storeRepo.DownloadFile(ctx, meta.S3Key)
	if err != nil {
		return nil, nil, err
	}
	return meta, data, nil
}

// DeleteFile verifies ownership, deletes the physical object from storage, and marks metadata record as deleted.
func (u *MediaUsecase) DeleteFile(ctx context.Context, userID, fileID string) error {
	if userID == "" {
		return ErrUnauthorized
	}
	meta, err := u.metaRepo.GetMetadata(ctx, fileID)
	if err != nil {
		return ErrFileNotFound
	}
	if meta.OwnerID != userID && userID != "admin" {
		return ErrAccessDenied
	}

	// 1. Delete physical file from storage
	_ = u.storeRepo.DeleteFile(ctx, meta.S3Key)

	// 2. Mark deleted in database
	return u.metaRepo.DeleteMetadata(ctx, fileID)
}
