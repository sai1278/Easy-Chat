package geo

import (
	"fmt"
	"math"
	"time"
)

const (
	// EarthRadiusMeters is the standard spherical Earth radius in meters.
	EarthRadiusMeters = 6371000.0

	// MaxChatDistanceMeters is the single backend source of truth for chat proximity (exactly 1.0 km).
	MaxChatDistanceMeters = 1000.0

	// MaxLocationAge defines the maximum allowed age of a location fix before it is deemed stale.
	MaxLocationAge = 60 * time.Second

	// MaxLocationAccuracyMeters defines the maximum permissible GPS horizontal inaccuracy.
	MaxLocationAccuracyMeters = 50.0

	// GoodAccuracyThreshold defines a high-precision GPS fix.
	GoodAccuracyThreshold = 25.0
)

// ProximityStatus represents the evaluation result code.
type ProximityStatus string

const (
	ProximityAllowed             ProximityStatus = "ALLOWED"
	ProximityOutsideRadius       ProximityStatus = "OUTSIDE_CHAT_RADIUS"
	ProximityStaleLocation       ProximityStatus = "LOCATION_STALE"
	ProximityStaleLocationLegacy ProximityStatus = "STALE_LOCATION"
	ProximityPoorAccuracy        ProximityStatus = "POOR_ACCURACY"
	ProximityLocationUnavailable ProximityStatus = "LOCATION_UNAVAILABLE"
	ProximityInvalidCoordinates  ProximityStatus = "INVALID_COORDINATES"
)

// LocationData captures authoritative user location information.
type LocationData struct {
	UserID         string    `json:"user_id"`
	Latitude       float64   `json:"latitude"`
	Longitude      float64   `json:"longitude"`
	AccuracyMeters float64   `json:"accuracy_meters"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// ProximityResult contains the outcome of a proximity evaluation.
type ProximityResult struct {
	Status                ProximityStatus `json:"status"`
	Allowed               bool            `json:"allowed"`
	DistanceMeters        float64         `json:"distance_meters"`
	DistanceDisplay       string          `json:"distance_display"`
	WithinChatRadius      bool            `json:"within_chat_radius"`
	MaxChatDistanceMeters float64         `json:"max_chat_distance_meters"`
	Message               string          `json:"message"`
}

// IsValidCoordinate checks whether latitude and longitude are within standard geographical ranges.
// Rejects NaN, Inf, out-of-range coordinates, and Null Island (0,0) uninitialized defaults.
func IsValidCoordinate(lat, lon float64) bool {
	if math.IsNaN(lat) || math.IsInf(lat, 0) || math.IsNaN(lon) || math.IsInf(lon, 0) {
		return false
	}
	if lat < -90.0 || lat > 90.0 {
		return false
	}
	if lon < -180.0 || lon > 180.0 {
		return false
	}
	if lat == 0.0 && lon == 0.0 {
		return false
	}
	return true
}

// HaversineDistance computes the geodesic distance in meters between two lat/lon coordinates.
// Formula:
// a = sin²((lat2-lat1)/2) + cos(lat1)*cos(lat2)*sin²((lon2-lon1)/2)
// c = 2 * atan2(sqrt(a), sqrt(1-a))
// distance = EarthRadius * c
func HaversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const degToRad = math.Pi / 180.0

	phi1 := lat1 * degToRad
	phi2 := lat2 * degToRad
	deltaPhi := (lat2 - lat1) * degToRad
	deltaLambda := (lon2 - lon1) * degToRad

	sinDeltaPhiHalf := math.Sin(deltaPhi / 2.0)
	sinDeltaLambdaHalf := math.Sin(deltaLambda / 2.0)

	a := sinDeltaPhiHalf*sinDeltaPhiHalf +
		math.Cos(phi1)*math.Cos(phi2)*sinDeltaLambdaHalf*sinDeltaLambdaHalf

	// Guard against floating point inaccuracies slightly exceeding 1.0
	if a > 1.0 {
		a = 1.0
	}

	c := 2.0 * math.Atan2(math.Sqrt(a), math.Sqrt(1.0-a))
	return EarthRadiusMeters * c
}

// FormatDistance formats distance into human-readable string.
// Displays meters e.g. "742 m" or kilometers e.g. "1.24 km".
func FormatDistance(meters float64) string {
	if meters < 0 {
		return "0 m"
	}
	if meters < 1000.0 {
		return fmt.Sprintf("%d m", int(math.Round(meters)))
	}
	km := meters / 1000.0
	return fmt.Sprintf("%.2f km", km)
}

// EvaluateProximity performs strict proximity, staleness, and accuracy validation between two locations.
func EvaluateProximity(locA, locB *LocationData, now time.Time) ProximityResult {
	res := ProximityResult{
		MaxChatDistanceMeters: MaxChatDistanceMeters,
	}

	if locA == nil || locB == nil {
		res.Status = ProximityLocationUnavailable
		res.Allowed = false
		res.Message = "Location unavailable for one or both users."
		return res
	}

	if !IsValidCoordinate(locA.Latitude, locA.Longitude) || !IsValidCoordinate(locB.Latitude, locB.Longitude) {
		res.Status = ProximityInvalidCoordinates
		res.Allowed = false
		res.Message = "Invalid geographic coordinates provided."
		return res
	}

	// Staleness check
	if now.Sub(locA.UpdatedAt) > MaxLocationAge || now.Sub(locB.UpdatedAt) > MaxLocationAge {
		res.Status = ProximityStaleLocation
		res.Allowed = false
		res.Message = "Location unavailable or outdated."
		return res
	}

	// Accuracy check
	if locA.AccuracyMeters > MaxLocationAccuracyMeters || locB.AccuracyMeters > MaxLocationAccuracyMeters {
		res.Status = ProximityPoorAccuracy
		res.Allowed = false
		res.Message = "Location accuracy is too poor for proximity verification."
		return res
	}

	dist := HaversineDistance(locA.Latitude, locA.Longitude, locB.Latitude, locB.Longitude)
	// Round to centimeters (2 decimal places) to eliminate IEEE 754 trigonometric floating-point artifacts
	dist = math.Round(dist*100.0) / 100.0
	res.DistanceMeters = dist
	res.DistanceDisplay = FormatDistance(dist)
	res.WithinChatRadius = dist <= MaxChatDistanceMeters

	if res.WithinChatRadius {
		res.Status = ProximityAllowed
		res.Allowed = true
		res.Message = "Users are within chat radius."
	} else {
		res.Status = ProximityOutsideRadius
		res.Allowed = false
		res.Message = "Users must be within 1 km to chat."
	}

	return res
}
