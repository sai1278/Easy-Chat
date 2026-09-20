package http

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
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

	// Extract optional room_id and message_id for zero-trust authorization binding
	roomID := r.FormValue("room_id")
	if roomID == "" {
		roomID = r.Header.Get("X-Room-Id")
	}
	if roomID == "" {
		roomID = r.URL.Query().Get("room_id")
	}

	messageID := r.FormValue("message_id")
	if messageID == "" {
		messageID = r.Header.Get("X-Message-Id")
	}
	if messageID == "" {
		messageID = r.URL.Query().Get("message_id")
	}

	// 3. Process upload through core use case
	meta, err := h.usecase.ProcessUpload(r.Context(), userID, header.Filename, contentType, roomID, messageID, fileBytes)
	if err != nil {
		if err == application.ErrUnauthorized {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}
		if err == application.ErrAccessDenied {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
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
	resp := map[string]interface{}{
		"file_id":      meta.ID,
		"url":          "/api/v1/media/download/" + meta.ID,
		"name":         meta.Name,
		"content_type": meta.ContentType,
		"size":         meta.Size,
		"room_id":      meta.RoomID,
		"message_id":   meta.MessageID,
		"created_at":   meta.CreatedAt,
	}
	_ = json.NewEncoder(w).Encode(resp)
}

// DownloadRedirectHandler serves the media file directly or redirects to S3/CDN after zero-trust room check.
func (h *MediaHandler) DownloadRedirectHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract file ID from path (e.g. /download/file_123 or /api/v1/media/download/file_123)
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) == 0 {
		http.Error(w, "Invalid path: missing file_id", http.StatusBadRequest)
		return
	}
	fileID := parts[len(parts)-1]

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized: missing user identity", http.StatusUnauthorized)
		return
	}

	// Extract optional room_id and message_id from query parameters or headers
	roomID := r.URL.Query().Get("room_id")
	if roomID == "" {
		roomID = r.Header.Get("X-Room-Id")
	}
	messageID := r.URL.Query().Get("message_id")
	if messageID == "" {
		messageID = r.Header.Get("X-Message-Id")
	}

	resp, err := h.usecase.GetSignedDownloadURL(r.Context(), userID, fileID, roomID, messageID, 15*time.Minute)
	if err != nil {
		if err == application.ErrUnauthorized {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}
		if err == application.ErrAccessDenied || err == application.ErrCrossRoomAccessDenied || err == application.ErrMessageDeleted {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
		if err == application.ErrFileNotFound || err == application.ErrMessageNotFound {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to authorize media access: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// If genuine remote CDN/S3 URL is present, redirect to offload download bandwidth
	if !strings.Contains(resp.URL, "localhost") && !strings.Contains(resp.URL, "download-mock") {
		http.Redirect(w, r, resp.URL, http.StatusTemporaryRedirect)
		return
	}

	// Local or fallback mode: stream stored file bytes directly
	meta, data, err := h.usecase.GetFileBytes(r.Context(), userID, fileID, roomID, messageID)
	if err != nil {
		if err == application.ErrUnauthorized {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}
		if err == application.ErrAccessDenied || err == application.ErrCrossRoomAccessDenied || err == application.ErrMessageDeleted {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
		if err == application.ErrFileNotFound || err == application.ErrMessageNotFound {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to stream media: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", meta.ContentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.Header().Set("Cache-Control", "private, no-cache, no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

// DeleteMediaHandler permanently deletes a media file and its metadata.
func (h *MediaHandler) DeleteMediaHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized: missing user identity", http.StatusUnauthorized)
		return
	}

	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) == 0 {
		http.Error(w, "Invalid path: missing file_id", http.StatusBadRequest)
		return
	}
	fileID := parts[len(parts)-1]

	if err := h.usecase.DeleteFile(r.Context(), userID, fileID); err != nil {
		if err == application.ErrUnauthorized {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}
		if err == application.ErrAccessDenied {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
		if err == application.ErrFileNotFound {
			http.Error(w, "File not found or already deleted", http.StatusNotFound)
			return
		}
		http.Error(w, "Delete failed: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"deleted","file_id":"` + fileID + `"}`))
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

	roomID := r.URL.Query().Get("room_id")
	if roomID == "" {
		roomID = r.Header.Get("X-Room-Id")
	}

	messageID := r.URL.Query().Get("message_id")
	if messageID == "" {
		messageID = r.Header.Get("X-Message-Id")
	}

	resp, err := h.usecase.GetSignedUploadURL(r.Context(), userID, fileName, roomID, messageID, 15*time.Minute)
	if err != nil {
		if err == application.ErrUnauthorized {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}
		if err == application.ErrAccessDenied {
			http.Error(w, err.Error(), http.StatusForbidden)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}
