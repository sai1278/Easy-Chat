package application

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/png"
	"strings"
	"sync"
	"testing"
	"time"

	"nearby/backend/services/media/internal/domain"
)

// MockMetadataRepository implements domain.MetadataRepository.
type MockMetadataRepository struct {
	mu    sync.RWMutex
	cache map[string]*domain.FileMetadata
}

func (m *MockMetadataRepository) SaveMetadata(ctx context.Context, meta *domain.FileMetadata) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cache == nil {
		m.cache = make(map[string]*domain.FileMetadata)
	}
	m.cache[meta.ID] = meta
	return nil
}

func (m *MockMetadataRepository) GetMetadata(ctx context.Context, id string) (*domain.FileMetadata, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	meta, exists := m.cache[id]
	if !exists {
		return nil, errors.New("not found")
	}
	return meta, nil
}

// MockStorageRepository implements domain.StorageRepository.
type MockStorageRepository struct {
	mu         sync.RWMutex
	store      map[string][]byte
	cdnEnabled bool
}

func (m *MockStorageRepository) UploadFile(ctx context.Context, key string, data []byte, contentType string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.store == nil {
		m.store = make(map[string][]byte)
	}
	m.store[key] = data
	return nil
}

func (m *MockStorageRepository) DownloadFile(ctx context.Context, key string) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	data, exists := m.store[key]
	if !exists {
		return nil, errors.New("not found")
	}
	return data, nil
}

func (m *MockStorageRepository) GeneratePreSignedUploadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	return "https://s3.mock.local/" + key + "?signed=true", nil
}

func (m *MockStorageRepository) GeneratePreSignedDownloadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	if m.cdnEnabled {
		return "https://cdn.mock.local/" + key, nil
	}
	return "https://s3.mock.local/" + key + "?signed=true", nil
}

// MockScannerPipeline implements domain.ScannerPipeline.
type MockScannerPipeline struct{}

func (m *MockScannerPipeline) Scan(ctx context.Context, data []byte) (bool, error) {
	// Standard EICAR signature rule
	eicarSig := []byte(`X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*`)
	if bytes.Contains(data, eicarSig) {
		return false, nil // Malware found
	}
	return true, nil // Clean
}

func TestMediaUsecase_ProcessUpload_SizeLimit(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Create payload larger than 10MB
	largeData := make([]byte, 11*1024*1024)

	_, err := usecase.ProcessUpload(context.Background(), "owner_1", "large.dat", "application/octet-stream", largeData)
	if err != ErrFileTooLarge {
		t.Errorf("expected ErrFileTooLarge, got %v", err)
	}
}

func TestMediaUsecase_ProcessUpload_MalwareDetection(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Ingest payload with EICAR malware test signature
	malwareData := []byte(`some header data X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H* trailing data`)

	_, err := usecase.ProcessUpload(context.Background(), "owner_1", "malware.txt", "text/plain", malwareData)
	if err != ErrVirusDetected {
		t.Errorf("expected ErrVirusDetected, got %v", err)
	}
}

func TestMediaUsecase_ProcessUpload_ImageCompression(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// 1. Generate 100x100 pixel PNG test image
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, img); err != nil {
		t.Fatalf("failed to encode PNG: %v", err)
	}
	rawPNGBytes := pngBuf.Bytes()

	// 2. Upload PNG and assert it was compressed/transcoded to JPEG format
	meta, err := usecase.ProcessUpload(context.Background(), "owner_1", "test.png", "image/png", rawPNGBytes)
	if err != nil {
		t.Fatalf("unexpected upload error: %v", err)
	}

	if meta.ContentType != "image/jpeg" {
		t.Errorf("expected content type to be transcoded to image/jpeg, got %s", meta.ContentType)
	}

	// Verify compressed file exists in storage
	compressedBytes, err := storeRepo.DownloadFile(context.Background(), meta.S3Key)
	if err != nil {
		t.Fatalf("failed to download stored file: %v", err)
	}

	if len(compressedBytes) == 0 {
		t.Error("compressed image payload is empty")
	}
}

func TestMediaUsecase_PreSignedURLs(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Setup mock metadata record
	meta := &domain.FileMetadata{
		ID:          "file-1",
		Name:        "test.dat",
		ContentType: "application/octet-stream",
		Size:        100,
		S3Key:       "media/owner_1/file-1",
		OwnerID:     "owner_1",
		CreatedAt:   time.Now(),
	}
	_ = metaRepo.SaveMetadata(context.Background(), meta)

	// Test Generate Download URL
	resp, err := usecase.GetSignedDownloadURL(context.Background(), "user_1", "file-1", 15*time.Minute)
	if err != nil {
		t.Fatalf("unexpected error generating download URL: %v", err)
	}

	if !strings.HasPrefix(resp.URL, "https://s3.mock.local/") {
		t.Errorf("unexpected pre-signed download URL prefix: %s", resp.URL)
	}

	// Test Generate Upload URL
	respUpload, err := usecase.GetSignedUploadURL(context.Background(), "owner_1", "upload.dat", 15*time.Minute)
	if err != nil {
		t.Fatalf("unexpected error generating upload URL: %v", err)
	}

	if !strings.HasPrefix(respUpload.URL, "https://s3.mock.local/") {
		t.Errorf("unexpected pre-signed upload URL prefix: %s", respUpload.URL)
	}
}
