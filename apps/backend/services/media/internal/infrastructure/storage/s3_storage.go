package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// S3StorageRepository implements domain.StorageRepository using standard AWS SDK.
type S3StorageRepository struct {
	client        *s3.Client
	presignClient *s3.PresignClient
	bucket        string
	cdnURL        string
	
	// Local fallback cache for zero-setup execution and tests
	localMu    sync.RWMutex
	localCache map[string][]byte
}

// NewS3StorageRepository creates a new S3StorageRepository.
func NewS3StorageRepository(client *s3.Client, bucket string, cdnURL string) *S3StorageRepository {
	var presignClient *s3.PresignClient
	if client != nil {
		presignClient = s3.NewPresignClient(client)
	}
	return &S3StorageRepository{
		client:        client,
		presignClient: presignClient,
		bucket:        bucket,
		cdnURL:        cdnURL,
		localCache:    make(map[string][]byte),
	}
}

// UploadFile streams and persists file bytes to S3 or local memory.
func (s *S3StorageRepository) UploadFile(ctx context.Context, key string, data []byte, contentType string) error {
	if s.client == nil {
		s.localMu.Lock()
		s.localCache[key] = data
		s.localMu.Unlock()
		return nil
	}

	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(data),
		ContentType: aws.String(contentType),
	})
	return err
}

// DownloadFile downloads file bytes from S3 or local memory.
func (s *S3StorageRepository) DownloadFile(ctx context.Context, key string) ([]byte, error) {
	if s.client == nil {
		s.localMu.RLock()
		data, exists := s.localCache[key]
		s.localMu.RUnlock()
		if !exists {
			return nil, errors.New("file not found")
		}
		return data, nil
	}

	resp, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}

// DeleteFile permanently deletes file bytes from S3 or local memory.
func (s *S3StorageRepository) DeleteFile(ctx context.Context, key string) error {
	if s.client == nil {
		s.localMu.Lock()
		delete(s.localCache, key)
		s.localMu.Unlock()
		return nil
	}

	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	return err
}

// GeneratePreSignedUploadURL returns a presigned S3 upload URL.
func (s *S3StorageRepository) GeneratePreSignedUploadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	if s.client == nil || s.presignClient == nil {
		return fmt.Sprintf("http://localhost:8086/api/v1/media/upload-mock?key=%s", key), nil
	}

	req, err := s.presignClient.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(expiry))
	if err != nil {
		return "", err
	}
	return req.URL, nil
}

// GeneratePreSignedDownloadURL returns a presigned S3 download URL (routes via CDN if cdnURL is present).
func (s *S3StorageRepository) GeneratePreSignedDownloadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	if s.cdnURL != "" {
		return fmt.Sprintf("%s/%s", s.cdnURL, key), nil
	}

	if s.client == nil || s.presignClient == nil {
		return fmt.Sprintf("http://localhost:8086/api/v1/media/download-mock?key=%s", key), nil
	}

	req, err := s.presignClient.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(expiry))
	if err != nil {
		return "", err
	}
	return req.URL, nil
}
