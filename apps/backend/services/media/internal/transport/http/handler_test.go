package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"nearby/backend/services/media/internal/application"
	"nearby/backend/services/media/internal/domain"
)

type mockMetaRepo struct {
	rooms    map[string]map[string]bool
	metadata map[string]*domain.FileMetadata
	messages map[string]bool
}

func (m *mockMetaRepo) SaveMetadata(ctx context.Context, meta *domain.FileMetadata) error {
	m.metadata[meta.ID] = meta
	return nil
}

func (m *mockMetaRepo) GetMetadata(ctx context.Context, id string) (*domain.FileMetadata, error) {
	meta, exists := m.metadata[id]
	if !exists {
		return nil, application.ErrFileNotFound
	}
	return meta, nil
}

func (m *mockMetaRepo) DeleteMetadata(ctx context.Context, id string) error {
	if meta, exists := m.metadata[id]; exists {
		meta.IsDeleted = true
	}
	return nil
}

func (m *mockMetaRepo) IsUserInRoom(ctx context.Context, userID, roomID string) (bool, error) {
	if m.rooms == nil {
		return false, nil
	}
	userMap, ok := m.rooms[roomID]
	if !ok {
		return false, nil
	}
	return userMap[userID], nil
}

func (m *mockMetaRepo) IsMessageActiveInRoom(ctx context.Context, messageID, roomID string) (bool, error) {
	isDel, exists := m.messages[messageID]
	if !exists {
		return false, application.ErrMessageNotFound
	}
	return !isDel, nil
}

type mockStoreRepo struct{}

func (m *mockStoreRepo) UploadFile(ctx context.Context, key string, data []byte, contentType string) error {
	return nil
}
func (m *mockStoreRepo) DownloadFile(ctx context.Context, key string) ([]byte, error) {
	return []byte("sample-data"), nil
}
func (m *mockStoreRepo) DeleteFile(ctx context.Context, key string) error {
	return nil
}
func (m *mockStoreRepo) GeneratePreSignedUploadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	return "https://s3.mock.local/" + key, nil
}
func (m *mockStoreRepo) GeneratePreSignedDownloadURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	return "https://s3.mock.local/" + key, nil
}

type mockScanner struct{}

func (m *mockScanner) Scan(ctx context.Context, data []byte) (bool, error) {
	return true, nil
}

func setupHandlerTest() *MediaHandler {
	repo := &mockMetaRepo{
		rooms: map[string]map[string]bool{
			"room-100": {"alice": true, "bob": true},
		},
		metadata: map[string]*domain.FileMetadata{
			"file-100": {
				ID:          "file-100",
				Name:        "image.jpg",
				ContentType: "image/jpeg",
				Size:        100,
				S3Key:       "media/alice/file-100",
				OwnerID:     "alice",
				RoomID:      "room-100",
				MessageID:   "msg-100",
				CreatedAt:   time.Now(),
			},
		},
		messages: map[string]bool{
			"msg-100": false,
		},
	}
	store := &mockStoreRepo{}
	scanner := &mockScanner{}
	usecase := application.NewMediaUsecase(repo, store, scanner)
	return NewMediaHandler(usecase)
}

func TestHTTP_MediaDownload_Unauthenticated_401(t *testing.T) {
	handler := setupHandlerTest()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media/download/file-100", nil)
	// Missing X-User-Id
	w := httptest.NewRecorder()
	handler.DownloadRedirectHandler(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got: %d", w.Code)
	}
}

func TestHTTP_MediaDownload_AuthenticatedRoomMember_200OrRedirect(t *testing.T) {
	handler := setupHandlerTest()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media/download/file-100?room_id=room-100&message_id=msg-100", nil)
	req.Header.Set("X-User-Id", "bob")
	w := httptest.NewRecorder()
	handler.DownloadRedirectHandler(w, req)

	if w.Code != http.StatusOK && w.Code != http.StatusTemporaryRedirect {
		t.Fatalf("expected 200 OK or 307 Redirect, got: %d (%s)", w.Code, w.Body.String())
	}
}

func TestHTTP_MediaDownload_UserOutsideRoom_403(t *testing.T) {
	handler := setupHandlerTest()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media/download/file-100?room_id=room-100&message_id=msg-100", nil)
	req.Header.Set("X-User-Id", "intruder")
	w := httptest.NewRecorder()
	handler.DownloadRedirectHandler(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden, got: %d (%s)", w.Code, w.Body.String())
	}
}

func TestHTTP_MediaDownload_CrossRoomAttempt_403(t *testing.T) {
	handler := setupHandlerTest()
	// Intruder claims room-999
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media/download/file-100?room_id=room-999&message_id=msg-100", nil)
	req.Header.Set("X-User-Id", "bob")
	w := httptest.NewRecorder()
	handler.DownloadRedirectHandler(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for cross-room attempt, got: %d (%s)", w.Code, w.Body.String())
	}
}

func TestHTTP_MediaDownload_NonexistentFile_404(t *testing.T) {
	handler := setupHandlerTest()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media/download/file-does-not-exist", nil)
	req.Header.Set("X-User-Id", "bob")
	w := httptest.NewRecorder()
	handler.DownloadRedirectHandler(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 Not Found, got: %d (%s)", w.Code, w.Body.String())
	}
}
