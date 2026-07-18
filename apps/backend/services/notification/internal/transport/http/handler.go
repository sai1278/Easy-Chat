package http

import (
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"

	"nearby/backend/services/notification/internal/domain"
)

type PreferenceHandler struct {
	prefRepo domain.PreferenceRepository
}

func NewPreferenceHandler(prefRepo domain.PreferenceRepository) *PreferenceHandler {
	return &PreferenceHandler{prefRepo: prefRepo}
}

// GetPreferencesHandler returns the user configuration settings with ETag caching.
func (h *PreferenceHandler) GetPreferencesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized: missing user ID header", http.StatusUnauthorized)
		return
	}

	pref, err := h.prefRepo.GetPreference(r.Context(), userID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Generate weak ETag based on preference state
	etag := fmt.Sprintf(`W/"%s-%v-%s-%s"`, pref.UserID, pref.EnablePush, pref.QuietHoursStart, pref.QuietHoursEnd)
	
	// Add Cache-Control and ETag headers
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "private, max-age=0, must-revalidate")

	// Verify If-None-Match condition
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(pref)
}

// UpdatePreferencesHandler saves changes to user push/quiet-hours options.
func (h *PreferenceHandler) UpdatePreferencesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut && r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req domain.NotificationPreference
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid json body", http.StatusBadRequest)
		return
	}

	req.UserID = userID // Enforce identity

	// Simple regex validation for quiet hour timestamps (Format: "HH:MM")
	timeRegex := regexp.MustCompile(`^(?:[01]\d|2[0-3]):[0-5]\d$`)
	if req.QuietHoursStart != "" && !timeRegex.MatchString(req.QuietHoursStart) {
		http.Error(w, "Invalid QuietHoursStart: must be HH:MM format", http.StatusBadRequest)
		return
	}
	if req.QuietHoursEnd != "" && !timeRegex.MatchString(req.QuietHoursEnd) {
		http.Error(w, "Invalid QuietHoursEnd: must be HH:MM format", http.StatusBadRequest)
		return
	}

	if err := h.prefRepo.SavePreference(r.Context(), &req); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(req)
}
