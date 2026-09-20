package http

import (
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"time"

	"nearby/backend/services/nearby/internal/application"
	"nearby/backend/services/nearby/internal/domain"
	"nearby/backend/shared/geo"
)

type LocationRequest struct {
	UserID            string   `json:"user_id,omitempty"`
	Latitude          float64  `json:"latitude"`
	Longitude         float64  `json:"longitude"`
	Accuracy          *float64 `json:"accuracy,omitempty"`
	AccuracyMeters    *float64 `json:"accuracy_meters,omitempty"`
	Timestamp         string   `json:"timestamp,omitempty"`
	LocationUpdatedAt string   `json:"location_updated_at,omitempty"`
}

type NearbyUserResponse struct {
	UserID                 string   `json:"user_id"`
	Pseudonym              string   `json:"pseudonym"`
	DisplayName            string   `json:"display_name"`
	AvatarURL              string   `json:"avatar_url"`
	Bio                    string   `json:"bio"`
	AvatarID               int32    `json:"avatar_id"`
	DistanceMeters         float64  `json:"distance_meters"`
	DistanceDisplay        string   `json:"distance_display"`
	WithinChatRadius       bool     `json:"within_chat_radius"`
	MaxChatDistanceMeters  float64  `json:"max_chat_distance_meters"`
	DistanceBucket         string   `json:"distance_bucket"`
	LocationAccuracyMeters *float64 `json:"location_accuracy_meters,omitempty"`
	AccuracyMeters         *float64 `json:"accuracy_meters,omitempty"`
	LocationUpdatedAt      string   `json:"location_updated_at,omitempty"`
	IsOnline               bool     `json:"is_online"`
	Latitude               float64  `json:"latitude,omitempty"`
	Longitude              float64  `json:"longitude,omitempty"`
}

type Handler struct {
	usecase  *application.NearbyUsecase
	geoRepo  domain.GeoRepository
	userRepo domain.UserRepository
}

func NewHandler(usecase *application.NearbyUsecase, geoRepo domain.GeoRepository, userRepo domain.UserRepository) *Handler {
	return &Handler{
		usecase:  usecase,
		geoRepo:  geoRepo,
		userRepo: userRepo,
	}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v1/nearby/location", h.HandleLocation)
	mux.HandleFunc("/location", h.HandleLocation)
	mux.HandleFunc("/api/v1/nearby/users", h.HandleGetUsers)
	mux.HandleFunc("/users", h.HandleGetUsers)
}

func (h *Handler) HandleLocation(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Method Not Allowed"})
		return
	}

	authUserID := r.Header.Get("X-User-Id")
	var req LocationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Invalid request body"})
		return
	}

	targetUserID := req.UserID
	if targetUserID == "" {
		targetUserID = authUserID
	}
	if targetUserID == "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Missing user_id"})
		return
	}

	// Security: Authenticated user cannot update another user's location
	if authUserID != "" && req.UserID != "" && authUserID != req.UserID {
		w.WriteHeader(http.StatusForbidden)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"code":    "FORBIDDEN",
			"message": "Cannot update location for another user",
		})
		return
	}

	// Validate geographic coordinates
	if !geo.IsValidCoordinate(req.Latitude, req.Longitude) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"code":    "INVALID_COORDINATES",
			"message": "Invalid latitude or longitude coordinates",
		})
		return
	}

	// Validate accuracy
	var reqAccuracy *float64
	if req.AccuracyMeters != nil {
		reqAccuracy = req.AccuracyMeters
	} else if req.Accuracy != nil {
		reqAccuracy = req.Accuracy
	}
	if reqAccuracy != nil {
		if *reqAccuracy <= 0 || *reqAccuracy > 10000 || math.IsNaN(*reqAccuracy) || math.IsInf(*reqAccuracy, 0) {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{
				"code":    "INVALID_ACCURACY",
				"message": "Location accuracy must be positive, finite, and within valid limits (<=10000m)",
			})
			return
		}
	}

	// Validate timestamp and freshness
	timeStr := req.LocationUpdatedAt
	if timeStr == "" {
		timeStr = req.Timestamp
	}
	locTime := time.Now().UTC()
	if timeStr != "" {
		parsed, err := time.Parse(time.RFC3339, timeStr)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{
				"code":    "INVALID_TIMESTAMP",
				"message": "Invalid timestamp format; must be RFC3339",
			})
			return
		}
		locTime = parsed.UTC()
		now := time.Now().UTC()
		// Reject stale updates older than 60 seconds
		if now.Sub(locTime) > geo.MaxLocationAge {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{
				"code":    "LOCATION_STALE",
				"message": "Location timestamp is stale (> 60 seconds old)",
			})
			return
		}
		// Reject future timestamps (> 60 seconds ahead)
		if locTime.Sub(now) > geo.MaxLocationAge {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{
				"code":    "INVALID_TIMESTAMP",
				"message": "Location timestamp cannot be in the future",
			})
			return
		}
	}

	// Save location update to Redis Geo Index and cache
	err := h.geoRepo.UpdateUserLocation(r.Context(), targetUserID, req.Latitude, req.Longitude, reqAccuracy, 60*time.Second, locTime)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	// Persist authoritative location to PostgreSQL user_locations table
	if h.userRepo != nil {
		var accVal float64 = 10.0
		if reqAccuracy != nil && *reqAccuracy > 0 {
			accVal = *reqAccuracy
		}
		_ = h.userRepo.UpsertUserLocation(r.Context(), targetUserID, req.Latitude, req.Longitude, accVal, locTime)
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *Handler) HandleGetUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Method Not Allowed"})
		return
	}

	userID := r.Header.Get("X-User-Id")
	q := r.URL.Query()
	latStr := q.Get("lat")
	lngStr := q.Get("lng")
	radiusStr := q.Get("radius")
	accStr := q.Get("accuracy")

	lat, err1 := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err1 != nil || err2 != nil || !geo.IsValidCoordinate(lat, lng) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Invalid or missing lat/lng parameters"})
		return
	}

	var reqAccuracy *float64
	if accStr != "" {
		if accVal, err := strconv.ParseFloat(accStr, 64); err == nil && accVal > 0 {
			reqAccuracy = &accVal
		}
	}

	radiusMeters := 5000
	if radiusStr != "" {
		if rVal, err := strconv.Atoi(radiusStr); err == nil && rVal > 0 {
			radiusMeters = rVal
		}
	}

	// Update requester's own location if user_id is provided
	if userID != "" {
		_ = h.geoRepo.UpdateUserLocation(r.Context(), userID, lat, lng, reqAccuracy, 60*time.Second)
		if h.userRepo != nil {
			var accVal float64 = 10.0
			if reqAccuracy != nil && *reqAccuracy > 0 {
				accVal = *reqAccuracy
			}
			_ = h.userRepo.UpsertUserLocation(r.Context(), userID, lat, lng, accVal)
		}
	}

	nearbyUsers, err := h.usecase.FindNearby(r.Context(), userID, lat, lng, radiusMeters, 20, 60*time.Second)
	if err != nil {
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode([]NearbyUserResponse{})
		return
	}

	respList := make([]NearbyUserResponse, 0, len(nearbyUsers))
	for _, u := range nearbyUsers {
		respList = append(respList, NearbyUserResponse{
			UserID:                 u.UserID,
			Pseudonym:              u.Pseudonym,
			DisplayName:            u.DisplayName,
			AvatarURL:              u.AvatarURL,
			Bio:                    u.Bio,
			AvatarID:               u.AvatarID,
			DistanceMeters:         u.DistanceMeters,
			DistanceDisplay:        u.DistanceDisplay,
			WithinChatRadius:       u.WithinChatRadius,
			MaxChatDistanceMeters:  u.MaxChatDistanceMeters,
			DistanceBucket:         u.DistanceBucket,
			LocationAccuracyMeters: u.AccuracyMeters,
			AccuracyMeters:         u.AccuracyMeters,
			LocationUpdatedAt:      u.LocationUpdatedAt,
			IsOnline:               true,
			Latitude:               lat,
			Longitude:              lng,
		})
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(respList)
}
