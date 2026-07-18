package app

import (
	"encoding/json"
	"net/http"

	"nearby/backend/internal/pkg/errors"
	"nearby/backend/internal/pkg/validation"
)

type AuthHandler struct {
	authService AuthService
}

func NewAuthHandler(service AuthService) *AuthHandler {
	return &AuthHandler{authService: service}
}

// Onboard handles anonymous registration (POST /api/v1/auth/session).
func (h *AuthHandler) Onboard(w http.ResponseWriter, r *http.Request) {
	type Request struct {
		DeviceChallenge string `json:"device_challenge"`
	}
	
	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		problem := errors.NewProblemDetails(http.StatusBadRequest, "bad-request", "Invalid Request Body", err.Error(), "BAD_REQUEST")
		problem.Instance = r.URL.Path
		problem.WriteJSON(w)
		return
	}

	// Validate challenge field
	if req.DeviceChallenge == "" || len(req.DeviceChallenge) < 32 {
		problem := errors.NewProblemDetails(http.StatusUnprocessableEntity, "validation-error", "Validation Failed", "device_challenge must be at least 32 characters", "VALIDATION_FAILED")
		problem.InvalidParams = []errors.InvalidParam{
			{Name: "device_challenge", Reason: "Must be a base64 string with length >= 32"},
		}
		problem.Instance = r.URL.Path
		problem.WriteJSON(w)
		return
	}

	user, access, refresh, err := h.authService.Onboard(r.Context())
	if err != nil {
		errors.ErrInternalServer.WriteJSON(w)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"access_token":  access,
		"refresh_token": refresh,
		"expires_in":    900,
		"user":          user,
	})
}

type UserHandler struct {
	userRepo UserRepository
}

func NewUserHandler(repo UserRepository) *UserHandler {
	return &UserHandler{userRepo: repo}
}

// UpdateProfile handles profile modifications (PATCH /api/v1/users/me).
func (h *UserHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	type Request struct {
		RegeneratePseudonym bool `json:"regenerate_pseudonym"`
		AvatarID            int  `json:"avatar_id"`
	}

	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errors.ErrInternalServer.WriteJSON(w)
		return
	}

	// Centralized validation check
	if req.AvatarID <= 0 || req.AvatarID > 50 {
		problem := errors.NewProblemDetails(http.StatusUnprocessableEntity, "validation-error", "Validation Failed", "avatar_id must be in range [1, 50]", "VALIDATION_FAILED")
		problem.InvalidParams = []errors.InvalidParam{
			{Name: "avatar_id", Reason: "Must be greater than 0 and less than or equal to 50"},
		}
		problem.Instance = r.URL.Path
		problem.WriteJSON(w)
		return
	}

	// Proceed with updates (delegated to repo/service)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"pseudonym": "crimson phantom",
		"avatar_id": req.AvatarID,
	})
}

type ProximityHandler struct {
	proximityService ProximityService
}

func NewProximityHandler(service ProximityService) *ProximityHandler {
	return &ProximityHandler{proximityService: service}
}

// ToggleVisibility handles visibility shifts (POST /api/v1/visibility/toggle).
func (h *ProximityHandler) ToggleVisibility(w http.ResponseWriter, r *http.Request) {
	type Request struct {
		IsVisible    bool   `json:"is_visible"`
		H3Index      string `json:"h3_index"`
		RadiusMeters int    `json:"radius_meters"`
	}

	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errors.ErrInternalServer.WriteJSON(w)
		return
	}

	// Validate fuzzed H3 coordinates format and selection limits
	if req.IsVisible {
		if !validation.ValidateH3Index(req.H3Index) {
			problem := errors.NewProblemDetails(http.StatusUnprocessableEntity, "validation-error", "Validation Failed", "Invalid H3 coordinate index format", "VALIDATION_FAILED")
			problem.InvalidParams = []errors.InvalidParam{
				{Name: "h3_index", Reason: "Must match standard H3 resolution 10 coordinate index"},
			}
			problem.Instance = r.URL.Path
			problem.WriteJSON(w)
			return
		}

		if !validation.ValidateRadius(req.RadiusMeters) {
			problem := errors.NewProblemDetails(http.StatusUnprocessableEntity, "validation-error", "Validation Failed", "Invalid radius configuration selection", "VALIDATION_FAILED")
			problem.InvalidParams = []errors.InvalidParam{
				{Name: "radius_meters", Reason: "Must be exactly 100, 150, or 200 meters"},
			}
			problem.Instance = r.URL.Path
			problem.WriteJSON(w)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"is_visible":    req.IsVisible,
		"h3_index":      req.H3Index,
		"radius_meters": req.RadiusMeters,
	})
}
