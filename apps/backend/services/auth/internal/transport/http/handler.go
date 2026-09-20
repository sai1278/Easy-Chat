package http

import (
	"encoding/json"
	"errors"
	"net/http"

	"nearby/backend/services/auth/internal/application"
	"nearby/backend/services/auth/internal/domain"
)

type AuthHandler struct {
	usecase *application.AuthUsecase
}

func NewAuthHandler(u *application.AuthUsecase) *AuthHandler {
	return &AuthHandler{usecase: u}
}

// Onboard handles registration profiles requests.
func (h *AuthHandler) Onboard(w http.ResponseWriter, r *http.Request) {
	type Request struct {
		DeviceID    string `json:"device_id"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		Username    string `json:"username"`
	}

	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"bad request"}`))
		return
	}

	user, err := h.usecase.Onboard(r.Context(), req.DeviceID, req.Password, req.DisplayName, req.Username)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		if errors.Is(err, domain.ErrRateLimitExceeded) {
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"rate limit exceeded"}`))
			return
		}
		if errors.Is(err, domain.ErrConflict) {
			w.WriteHeader(http.StatusConflict)
			_, _ = w.Write([]byte(`{"error":"conflict: device already registered"}`))
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"internal server error"}`))
		return
	}

	body, err := json.Marshal(user)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"internal server error"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_, _ = w.Write(body)
}

// Login initiates access session handshakes.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	type Request struct {
		DeviceID string `json:"device_id"`
		Password string `json:"password"`
	}

	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"bad request"}`))
		return
	}

	accessToken, refreshToken, err := h.usecase.Login(r.Context(), req.DeviceID, req.Password)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
		return
	}

	payload := map[string]string{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"internal server error"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}
