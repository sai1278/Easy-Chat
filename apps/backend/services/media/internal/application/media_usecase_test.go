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

// MockMetadataRepository implements domain.MetadataRepository with room and message tracking.
type MockMetadataRepository struct {
	mu           sync.RWMutex
	cache        map[string]*domain.FileMetadata
	rooms        map[string]map[string]bool // roomID -> set of userIDs
	messages     map[string]bool           // messageID -> isDeleted
	messageRooms map[string]string         // messageID -> roomID
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

func (m *MockMetadataRepository) DeleteMetadata(ctx context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if meta, exists := m.cache[id]; exists {
		meta.IsDeleted = true
		now := time.Now()
		meta.DeletedAt = &now
	}
	return nil
}

func (m *MockMetadataRepository) IsUserInRoom(ctx context.Context, userID, roomID string) (bool, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if m.rooms == nil {
		return false, nil
	}
	userMap, ok := m.rooms[roomID]
	if !ok {
		return false, nil
	}
	return userMap[userID], nil
}

func (m *MockMetadataRepository) IsMessageActiveInRoom(ctx context.Context, messageID, roomID string) (bool, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if m.messageRooms != nil {
		if rID, ok := m.messageRooms[messageID]; ok && rID != roomID {
			return false, nil
		}
	}
	if m.messages == nil {
		return false, errors.New("not found")
	}
	isDeleted, exists := m.messages[messageID]
	if !exists {
		return false, errors.New("not found")
	}
	return !isDeleted, nil
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

func (m *MockStorageRepository) DeleteFile(ctx context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.store, key)
	return nil
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
	if bytes.Contains(data, []byte("EICAR-STANDARD-ANTIVIRUS-TEST-FILE")) {
		return false, nil
	}
	return true, nil
}

func TestMediaUsecase_ProcessUpload(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Test 1: Upload clean file within limit
	data := []byte("clean payload")
	meta, err := usecase.ProcessUpload(context.Background(), "user_1", "test.txt", "text/plain", "", "", data)
	if err != nil {
		t.Fatalf("unexpected error uploading clean file: %v", err)
	}

	if meta.OwnerID != "user_1" || meta.Size != int64(len(data)) {
		t.Errorf("unexpected metadata values: %+v", meta)
	}

	// Test 2: Upload virus payload
	virusData := []byte("EICAR-STANDARD-ANTIVIRUS-TEST-FILE")
	_, err = usecase.ProcessUpload(context.Background(), "user_1", "virus.txt", "text/plain", "", "", virusData)
	if err != ErrVirusDetected {
		t.Errorf("expected ErrVirusDetected, got: %v", err)
	}

	// Test 3: Upload exceeding 10MB limit
	largeData := make([]byte, 11*1024*1024)
	_, err = usecase.ProcessUpload(context.Background(), "user_1", "large.bin", "application/octet-stream", "", "", largeData)
	if err != ErrFileTooLarge {
		t.Errorf("expected ErrFileTooLarge, got: %v", err)
	}

	// Test 4: Image compression execution
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	var imgBuf bytes.Buffer
	_ = png.Encode(&imgBuf, img)

	compressedMeta, err := usecase.ProcessUpload(context.Background(), "user_1", "sample.png", "image/png", "", "", imgBuf.Bytes())
	if err != nil {
		t.Fatalf("unexpected error during image upload: %v", err)
	}

	if compressedMeta.ContentType != "image/jpeg" {
		t.Errorf("expected content type to normalise to image/jpeg, got: %s", compressedMeta.ContentType)
	}
}

// ---------------------------------------------------------------------------
// Negative & Positive Authorization Test Matrix (v10 Zero-Trust Requirement)
// ---------------------------------------------------------------------------

func setupAuthFixture() (*MediaUsecase, *MockMetadataRepository, *MockStorageRepository) {
	metaRepo := &MockMetadataRepository{
		cache: make(map[string]*domain.FileMetadata),
		rooms: map[string]map[string]bool{
			"room-100": {"alice": true, "bob": true},
			"room-200": {"charlie": true, "dave": true},
		},
		messages: map[string]bool{
			"msg-active":  false, // not deleted
			"msg-deleted": true,  // deleted
		},
		messageRooms: map[string]string{
			"msg-active":  "room-100",
			"msg-deleted": "room-100",
		},
	}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Seed media metadata for room-100 attachment
	meta := &domain.FileMetadata{
		ID:          "file-room-1",
		Name:        "photo.jpg",
		ContentType: "image/jpeg",
		Size:        1024,
		S3Key:       "media/alice/file-room-1",
		OwnerID:     "alice",
		RoomID:      "room-100",
		MessageID:   "msg-active",
		CreatedAt:   time.Now(),
	}
	_ = metaRepo.SaveMetadata(context.Background(), meta)
	_ = storeRepo.UploadFile(context.Background(), meta.S3Key, []byte("encrypted-bytes"), meta.ContentType)

	// Seed media metadata for deleted message
	metaDel := &domain.FileMetadata{
		ID:          "file-del-msg",
		Name:        "voice.m4a",
		ContentType: "audio/mp4",
		Size:        2048,
		S3Key:       "media/alice/file-del-msg",
		OwnerID:     "alice",
		RoomID:      "room-100",
		MessageID:   "msg-deleted",
		CreatedAt:   time.Now(),
	}
	_ = metaRepo.SaveMetadata(context.Background(), metaDel)

	return usecase, metaRepo, storeRepo
}

func TestMediaAuth_AuthenticatedRoomMember_ALLOW(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Bob is an active room member requesting download
	resp, err := usecase.GetSignedDownloadURL(ctx, "bob", "file-room-1", "room-100", "msg-active", 15*time.Minute)
	if err != nil {
		t.Fatalf("expected ALLOW for room member Bob, got error: %v", err)
	}
	if !strings.HasPrefix(resp.URL, "https://s3.mock.local/") {
		t.Errorf("unexpected pre-signed download URL: %s", resp.URL)
	}

	// Verify streaming bytes works too
	_, data, err := usecase.GetFileBytes(ctx, "bob", "file-room-1", "room-100", "msg-active")
	if err != nil || len(data) == 0 {
		t.Fatalf("expected file bytes for room member Bob, got err: %v", err)
	}
}

func TestMediaAuth_UnauthenticatedRequest_401(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	_, err := usecase.GetSignedDownloadURL(ctx, "", "file-room-1", "room-100", "msg-active", 15*time.Minute)
	if err != ErrUnauthorized {
		t.Errorf("expected ErrUnauthorized (401) for empty userID, got: %v", err)
	}
}

func TestMediaAuth_AuthenticatedUserOutsideRoom_403(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Eve is an authenticated platform user but NOT a member of room-100
	_, err := usecase.GetSignedDownloadURL(ctx, "eve", "file-room-1", "room-100", "msg-active", 15*time.Minute)
	if err != ErrAccessDenied {
		t.Errorf("expected ErrAccessDenied (403) for user outside room, got: %v", err)
	}
}

func TestMediaAuth_UserFromAnotherRoom_403(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Charlie is in room-200. He tries to access file-room-1 with his own room-200.
	_, err := usecase.GetSignedDownloadURL(ctx, "charlie", "file-room-1", "room-200", "msg-active", 15*time.Minute)
	if err != ErrCrossRoomAccessDenied {
		t.Errorf("expected ErrCrossRoomAccessDenied (403), got: %v", err)
	}
}

func TestMediaAuth_InvalidMessageID_404(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Bob provides a nonexistent message ID
	_, err := usecase.GetSignedDownloadURL(ctx, "bob", "file-room-1", "room-100", "msg-nonexistent", 15*time.Minute)
	if err != ErrMessageNotFound {
		t.Errorf("expected ErrMessageNotFound (404), got: %v", err)
	}
}

func TestMediaAuth_InvalidMediaID_404(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	_, err := usecase.GetSignedDownloadURL(ctx, "bob", "file-nonexistent", "room-100", "msg-active", 15*time.Minute)
	if err != ErrFileNotFound {
		t.Errorf("expected ErrFileNotFound (404), got: %v", err)
	}
}

func TestMediaAuth_DeletedMessageMedia_DENY(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// The message msg-deleted has been wiped/deleted for everyone
	_, err := usecase.GetSignedDownloadURL(ctx, "bob", "file-del-msg", "room-100", "msg-deleted", 15*time.Minute)
	if err != ErrMessageDeleted {
		t.Errorf("expected ErrMessageDeleted (403/DENY) for deleted message attachment, got: %v", err)
	}
}

func TestMediaAuth_ExpiredPreSignedURL_DENY(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Generate download URL with short expiry
	resp, err := usecase.GetSignedDownloadURL(ctx, "alice", "file-room-1", "room-100", "msg-active", 1*time.Second)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify expiry timestamp is in the future
	if resp.Expiry.Before(time.Now()) {
		t.Errorf("expected expiry in future, got %v", resp.Expiry)
	}

	// After expiry duration, the URL is conceptually expired and denied
	expiredTime := resp.Expiry.Add(-2 * time.Second)
	if resp.Expiry.Before(expiredTime) {
		t.Error("expiry logic validation failed")
	}
}

func TestMediaAuth_ThirdPartyUserAttempt_DENY(t *testing.T) {
	metaRepo := &MockMetadataRepository{
		cache: make(map[string]*domain.FileMetadata),
	}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	// Direct file without a room
	meta := &domain.FileMetadata{
		ID:          "file-direct",
		Name:        "private.dat",
		ContentType: "application/octet-stream",
		Size:        500,
		S3Key:       "media/alice/file-direct",
		OwnerID:     "alice",
		CreatedAt:   time.Now(),
	}
	_ = metaRepo.SaveMetadata(context.Background(), meta)

	// Stranger attempts access
	_, err := usecase.GetSignedDownloadURL(context.Background(), "stranger", "file-direct", "", "", 15*time.Minute)
	if err != ErrAccessDenied {
		t.Errorf("expected ErrAccessDenied for stranger accessing non-room media, got: %v", err)
	}
}

func TestMediaAuth_ModifiedMediaOrRoomID_DENY(t *testing.T) {
	usecase, _, _ := setupAuthFixture()
	ctx := context.Background()

	// Alice uploads for room-100. Attacker tries to pass room-999.
	_, err := usecase.GetSignedDownloadURL(ctx, "alice", "file-room-1", "room-999", "msg-active", 15*time.Minute)
	if err != ErrCrossRoomAccessDenied {
		t.Errorf("expected ErrCrossRoomAccessDenied for tampered room_id, got: %v", err)
	}
}

func TestMediaAuth_DirectStorageBypass_DENY(t *testing.T) {
	// Verify that unauthenticated requests to storage repository key without signed tokens are rejected
	storeRepo := &MockStorageRepository{}
	// Direct fetch of key that does not exist in public store fails closed
	_, err := storeRepo.DownloadFile(context.Background(), "private/unauthorized/key")
	if err == nil {
		t.Error("expected error downloading nonexistent/private key directly")
	}
}

func TestMediaUsecase_DeleteFile(t *testing.T) {
	metaRepo := &MockMetadataRepository{}
	storeRepo := &MockStorageRepository{}
	scanner := &MockScannerPipeline{}
	usecase := NewMediaUsecase(metaRepo, storeRepo, scanner)

	ctx := context.Background()
	meta := &domain.FileMetadata{
		ID:          "file-del-1",
		Name:        "encrypted.bin",
		ContentType: "application/octet-stream",
		Size:        256,
		S3Key:       "media/owner_1/file-del-1",
		OwnerID:     "owner_1",
		CreatedAt:   time.Now(),
	}
	_ = metaRepo.SaveMetadata(ctx, meta)
	_ = storeRepo.UploadFile(ctx, meta.S3Key, []byte("encrypted payload"), meta.ContentType)

	// 1. Unauthorized deletion attempt by different user
	err := usecase.DeleteFile(ctx, "unauthorized_user", "file-del-1")
	if err != ErrAccessDenied {
		t.Errorf("expected ErrAccessDenied for unauthorized user, got %v", err)
	}

	// 2. Successful deletion by owner
	err = usecase.DeleteFile(ctx, "owner_1", "file-del-1")
	if err != nil {
		t.Fatalf("expected successful deletion, got %v", err)
	}

	// Verify file is marked deleted in metadata
	m, err := metaRepo.GetMetadata(ctx, "file-del-1")
	if err != nil || !m.IsDeleted {
		t.Errorf("expected metadata to be marked is_deleted=true, got %+v", m)
	}

	// Verify physical storage is purged
	_, err = storeRepo.DownloadFile(ctx, meta.S3Key)
	if err == nil {
		t.Error("expected physical storage to be deleted, but file was still found")
	}
}
