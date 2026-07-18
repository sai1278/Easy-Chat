package http

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"nearby/backend/services/media/internal/application"
)

type MediaHandler struct {
	usecase *application.MediaUsecase
}

func NewMediaHandler(usecase *application.MediaUsecase) *MediaHandler {
	return &MediaHandler{usecase: usecase}
}

// UploadHandler processes multipart uploads, performing size limit enforcement, compression, scanning, and S3 upload.
func (h *MediaHandler) UploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 1. Authenticate user from gateway proxy header
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized: missing user identity", http.StatusUnauthorized)
		return
	}

	// 2. Enforce 10MB max body size limit at HTTP reader level
	r.Body = http.MaxBytesReader(w, r.Body, 10*1024*1024)
	err := r.ParseMultipartForm(10 * 1024 * 1024)
	if err != nil {
		http.Error(w, "File too large: maximum 10MB allowed", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Missing file parameter", http.StatusBadRequest)
		return
	}
	defer file.Close()

	fileBytes, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "Failed to read file bytes", http.StatusInternalServerError)
		return
	}

	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	// 3. Process upload through core use case
	meta, err := h.usecase.ProcessUpload(r.Context(), userID, header.Filename, contentType, fileBytes)
	if err != nil {
		if err == application.ErrFileTooLarge || err == application.ErrVirusDetected {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"` + err.Error() + `"}`))
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(meta)
}

// DownloadRedirectHandler redirects the request directly to the presigned S3/CDN URL to optimize download performance.
func (h *MediaHandler) DownloadRedirectHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract file ID from path (e.g. /api/v1/media/download/file_123)
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 5 {
		http.Error(w, "Invalid path: missing file_id", http.StatusBadRequest)
		return
	}
	fileID := parts[len(parts)-1]

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		userID = "anonymous" // Allow read access for stub
	}

	resp, err := h.usecase.GetSignedDownloadURL(r.Context(), userID, fileID, 15*time.Minute)
	if err != nil {
		if err == application.ErrAccessDenied {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	// Redirect to offload download bandwidth to CDN / S3
	http.Redirect(w, r, resp.URL, http.StatusTemporaryRedirect)
}

// SignedUploadURLHandler generates pre-signed upload destinations.
func (h *MediaHandler) SignedUploadURLHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	fileName := r.URL.Query().Get("name")
	if fileName == "" {
		fileName = "attachment.dat"
	}

	resp, err := h.usecase.GetSignedUploadURL(r.Context(), userID, fileName, 15*time.Minute)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}
