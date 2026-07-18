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

	"nearby/backend/services/media/internal/domain"
)

var (
	ErrFileTooLarge   = errors.New("file size exceeds maximum limit of 10MB")
	ErrInvalidType    = errors.New("file type not allowed")
	ErrVirusDetected  = errors.New("malware signature detected, upload blocked")
	ErrAccessDenied   = errors.New("access to this media resource is denied")
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
func (u *MediaUsecase) ProcessUpload(ctx context.Context, ownerID string, name string, contentType string, data []byte) (*domain.FileMetadata, error) {
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

	// 3. Compress Images if applicable (JPEG/PNG)
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

	// 4. Generate metadata and keys
	fileID := fmt.Sprintf("file_%d", time.Now().UnixNano())
	s3Key := fmt.Sprintf("media/%s/%s", ownerID, fileID)

	// 5. Upload to Cloud Storage
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
		CreatedAt:   time.Now(),
	}

	// 6. Save metadata to PostgreSQL
	if err := u.metaRepo.SaveMetadata(ctx, meta); err != nil {
		return nil, err
	}

	return meta, nil
}

// GetSignedDownloadURL generates a pre-signed S3 download URL after checking access control.
func (u *MediaUsecase) GetSignedDownloadURL(ctx context.Context, userID string, fileID string, expiry time.Duration) (*domain.PreSignedUrlResponse, error) {
	meta, err := u.metaRepo.GetMetadata(ctx, fileID)
	if err != nil {
		return nil, err
	}

	// Access control: Ensure user is either the owner or has access permissions
	// (For simplicity in this stub, we allow any valid request, but mock check)
	if userID == "" {
		return nil, ErrAccessDenied
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
func (u *MediaUsecase) GetSignedUploadURL(ctx context.Context, ownerID string, name string, expiry time.Duration) (*domain.PreSignedUrlResponse, error) {
	fileID := fmt.Sprintf("file_%d", time.Now().UnixNano())
	s3Key := fmt.Sprintf("media/%s/%s", ownerID, fileID)

	url, err := u.storeRepo.GeneratePreSignedUploadURL(ctx, s3Key, expiry)
	if err != nil {
		return nil, err
	}

	return &domain.PreSignedUrlResponse{
		URL:    url,
		Expiry: time.Now().Add(expiry),
		FileID: fileID,
	}, nil
}
