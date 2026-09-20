package geo

import (
	"math"
	"testing"
	"time"
)

func TestHaversineDistanceIdenticalPoint(t *testing.T) {
	dist := HaversineDistance(17.385044, 78.486671, 17.385044, 78.486671)
	if dist != 0.0 {
		t.Fatalf("expected 0 distance, got %f", dist)
	}
}

func TestHaversineDistanceKnownPoints(t *testing.T) {
	// Hyderabad Charminar (17.3616, 78.4747) to Golconda Fort (17.3833, 78.4011)
	// Known geodesic distance is approximately 8,160 meters
	dist := HaversineDistance(17.3616, 78.4747, 17.3833, 78.4011)
	if dist < 8100 || dist > 8250 {
		t.Fatalf("expected distance ~8160m, got %f", dist)
	}
}

// offsetLatForDistance calculates delta latitude for a target distance in meters along meridian
func offsetLatForDistance(meters float64) float64 {
	// 1 degree latitude = EarthRadius * (pi / 180) meters
	return meters / (EarthRadiusMeters * (math.Pi / 180.0))
}

func TestBoundaryDistances(t *testing.T) {
	baseLat := 17.440081
	baseLon := 78.348916
	now := time.Now()

	testCases := []struct {
		targetMeters float64
		expectAllow  bool
		description  string
	}{
		{0.0, true, "0m co-located"},
		{10.0, true, "10m very close"},
		{100.0, true, "100m nearby"},
		{500.0, true, "500m halfway"},
		{750.0, true, "750m within boundary"},
		{999.0, true, "999m boundary ALLOW"},
		{999.9, true, "999.9m boundary ALLOW"},
		{1000.0, true, "1000.0m exact boundary ALLOW"},
		{1000.1, false, "1000.1m boundary BLOCK"},
		{1001.0, false, "1001m boundary BLOCK"},
		{1500.0, false, "1500m outside BLOCK"},
		{5000.0, false, "5000m distant BLOCK"},
		{10000.0, false, "10000m far BLOCK"},
	}

	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			dLat := offsetLatForDistance(tc.targetMeters)
			targetLat := baseLat + dLat

			locA := &LocationData{
				UserID:         "user-a",
				Latitude:       baseLat,
				Longitude:      baseLon,
				AccuracyMeters: 5.0,
				UpdatedAt:      now,
			}
			locB := &LocationData{
				UserID:         "user-b",
				Latitude:       targetLat,
				Longitude:      baseLon,
				AccuracyMeters: 5.0,
				UpdatedAt:      now,
			}

			result := EvaluateProximity(locA, locB, now)

			// Tolerated delta for floating point Haversine calculation vs linear meridian offset
			delta := math.Abs(result.DistanceMeters - tc.targetMeters)
			if delta > 0.05 {
				t.Fatalf("expected distance close to %f, got %f (delta %f)", tc.targetMeters, result.DistanceMeters, delta)
			}

			if result.Allowed != tc.expectAllow {
				t.Fatalf("test %s: expected Allowed=%v, got %v (distance=%.12f, diff from 1000=%.12f)",
					tc.description, tc.expectAllow, result.Allowed, result.DistanceMeters, result.DistanceMeters-1000.0)
			}
		})
	}
}

func TestStaleLocation(t *testing.T) {
	now := time.Now()
	baseLat := 17.440081
	baseLon := 78.348916

	// A updated 10 seconds ago, B updated 20 seconds ago -> valid
	locA := &LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 10, UpdatedAt: now.Add(-10 * time.Second)}
	locB := &LocationData{UserID: "b", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 10, UpdatedAt: now.Add(-20 * time.Second)}
	res := EvaluateProximity(locA, locB, now)
	if !res.Allowed {
		t.Fatalf("expected valid proximity for fresh locations, got %s", res.Status)
	}

	// A updated 5 minutes ago, B updated 10 seconds ago -> stale
	locAStale := &LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 10, UpdatedAt: now.Add(-5 * time.Minute)}
	resStale := EvaluateProximity(locAStale, locB, now)
	if resStale.Allowed || resStale.Status != ProximityStaleLocation {
		t.Fatalf("expected ProximityStaleLocation, got %s (allowed=%v)", resStale.Status, resStale.Allowed)
	}
}

func TestAccuracyThresholds(t *testing.T) {
	now := time.Now()
	baseLat := 17.440081
	baseLon := 78.348916

	// A=5m, B=8m -> valid
	locA := &LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 5, UpdatedAt: now}
	locB := &LocationData{UserID: "b", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 8, UpdatedAt: now}
	res := EvaluateProximity(locA, locB, now)
	if !res.Allowed {
		t.Fatalf("expected allowed for good accuracy, got %s", res.Status)
	}

	// A=50m, B=45m -> valid
	locA50 := &LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 50, UpdatedAt: now}
	locB45 := &LocationData{UserID: "b", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 45, UpdatedAt: now}
	resAcceptable := EvaluateProximity(locA50, locB45, now)
	if !resAcceptable.Allowed {
		t.Fatalf("expected allowed for acceptable accuracy <=50m, got %s", resAcceptable.Status)
	}

	// A=150m, B=10m -> poor accuracy rejected
	locA150 := &LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 150, UpdatedAt: now}
	resPoor := EvaluateProximity(locA150, locB, now)
	if resPoor.Allowed || resPoor.Status != ProximityPoorAccuracy {
		t.Fatalf("expected ProximityPoorAccuracy, got %s (allowed=%v)", resPoor.Status, resPoor.Allowed)
	}
}

func TestFormatDistance(t *testing.T) {
	if s := FormatDistance(0); s != "0 m" {
		t.Fatalf("expected '0 m', got '%s'", s)
	}
	if s := FormatDistance(742.35); s != "742 m" {
		t.Fatalf("expected '742 m', got '%s'", s)
	}
	if s := FormatDistance(999.4); s != "999 m" {
		t.Fatalf("expected '999 m', got '%s'", s)
	}
	if s := FormatDistance(1000.0); s != "1.00 km" {
		t.Fatalf("expected '1.00 km', got '%s'", s)
	}
	if s := FormatDistance(1247.4); s != "1.25 km" {
		t.Fatalf("expected '1.25 km', got '%s'", s)
	}
}

func TestInvalidCoordinates(t *testing.T) {
	now := time.Now()
	locValid := &LocationData{UserID: "a", Latitude: 17.0, Longitude: 78.0, AccuracyMeters: 10, UpdatedAt: now}
	locInvalidLat := &LocationData{UserID: "b", Latitude: 95.0, Longitude: 78.0, AccuracyMeters: 10, UpdatedAt: now}
	locNullIsland := &LocationData{UserID: "c", Latitude: 0.0, Longitude: 0.0, AccuracyMeters: 10, UpdatedAt: now}
	locNaN := &LocationData{UserID: "d", Latitude: math.NaN(), Longitude: 78.0, AccuracyMeters: 10, UpdatedAt: now}
	locInf := &LocationData{UserID: "e", Latitude: 17.0, Longitude: math.Inf(1), AccuracyMeters: 10, UpdatedAt: now}

	res := EvaluateProximity(locValid, locInvalidLat, now)
	if res.Allowed || res.Status != ProximityInvalidCoordinates {
		t.Fatalf("expected ProximityInvalidCoordinates for lat 95, got %s", res.Status)
	}

	resNull := EvaluateProximity(locValid, locNullIsland, now)
	if resNull.Allowed || resNull.Status != ProximityInvalidCoordinates {
		t.Fatalf("expected ProximityInvalidCoordinates for Null Island (0,0), got %s", resNull.Status)
	}

	resNaN := EvaluateProximity(locValid, locNaN, now)
	if resNaN.Allowed || resNaN.Status != ProximityInvalidCoordinates {
		t.Fatalf("expected ProximityInvalidCoordinates for NaN, got %s", resNaN.Status)
	}

	resInf := EvaluateProximity(locValid, locInf, now)
	if resInf.Allowed || resInf.Status != ProximityInvalidCoordinates {
		t.Fatalf("expected ProximityInvalidCoordinates for Inf, got %s", resInf.Status)
	}
}
