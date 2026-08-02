package http

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"nearby/backend/services/nearby/internal/application"
	"nearby/backend/services/nearby/internal/domain"
)

type LocationRequest struct {
	UserID    string  `json:"user_id,omitempty"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Timestamp string  `json:"timestamp,omitempty"`
}

type NearbyUserResponse struct {
	UserID         string  `json:"user_id"`
	Pseudonym      string  `json:"pseudonym"`
	AvatarID       int32   `json:"avatar_id"`
	DistanceMeters float64 `json:"distance_meters"`
	DistanceBucket string  `json:"distance_bucket"`
	IsOnline       bool    `json:"is_online"`
	Latitude       float64 `json:"latitude,omitempty"`
	Longitude      float64 `json:"longitude,omitempty"`
}

type Handler struct {
	usecase *application.NearbyUsecase
	geoRepo domain.GeoRepository
}

func NewHandler(usecase *application.NearbyUsecase, geoRepo domain.GeoRepository) *Handler {
	return &Handler{
		usecase: usecase,
		geoRepo: geoRepo,
	}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v1/nearby/location", h.HandleLocation)
	mux.HandleFunc("/location", h.HandleLocation)
	mux.HandleFunc("/api/v1/nearby/users", h.HandleGetUsers)
	mux.HandleFunc("/users", h.HandleGetUsers)
}

func (h *Handler) HandleLocation(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	var req LocationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if userID == "" {
		userID = req.UserID
	}
	if userID == "" {
		http.Error(w, "Missing user_id", http.StatusBadRequest)
		return
	}

	// Save location update to Redis Geo Index with 60s TTL
	err := h.geoRepo.UpdateUserLocation(r.Context(), userID, req.Latitude, req.Longitude, 60*time.Second)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *Handler) HandleGetUsers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	userID := r.Header.Get("X-User-Id")
	q := r.URL.Query()
	latStr := q.Get("lat")
	lngStr := q.Get("lng")
	radiusStr := q.Get("radius")

	lat, err1 := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err1 != nil || err2 != nil {
		http.Error(w, "Invalid or missing lat/lng parameters", http.StatusBadRequest)
		return
	}

	radiusMeters := 5000
	if radiusStr != "" {
		if rVal, err := strconv.Atoi(radiusStr); err == nil && rVal > 0 {
			radiusMeters = rVal
		}
	}

	// Update requester's own location if user_id is provided
	if userID != "" {
		_ = h.geoRepo.UpdateUserLocation(r.Context(), userID, lat, lng, 60*time.Second)
	}

	nearbyUsers, err := h.usecase.FindNearby(r.Context(), userID, lat, lng, radiusMeters, 20, 60*time.Second)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode([]NearbyUserResponse{})
		return
	}

	respList := make([]NearbyUserResponse, 0, len(nearbyUsers))
	for _, u := range nearbyUsers {
		respList = append(respList, NearbyUserResponse{
			UserID:         u.UserID,
			Pseudonym:      u.Pseudonym,
			AvatarID:       u.AvatarID,
			DistanceMeters: u.DistanceMeters,
			DistanceBucket: u.DistanceBucket,
			IsOnline:       true,
			Latitude:       lat,
			Longitude:      lng,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(respList)
}
