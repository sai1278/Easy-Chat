package application

import (
	"encoding/json"
	"fmt"
	"math"
	"testing"
	"time"

	"nearby/backend/shared/geo"
)

// mockLocationProvider implements basic in-memory location testing for ProximityValidator logic
func offsetLatForDistance(meters float64) float64 {
	return meters / (geo.EarthRadiusMeters * (math.Pi / 180.0))
}

func TestProximityValidator_EvaluateBoundaries(t *testing.T) {
	baseLat := 17.440081
	baseLon := 78.348916
	now := time.Now().UTC()

	cases := []struct {
		distMeters   float64
		expectedCode geo.ProximityStatus
		allowed      bool
	}{
		{0.0, geo.ProximityAllowed, true},
		{10.0, geo.ProximityAllowed, true},
		{100.0, geo.ProximityAllowed, true},
		{500.0, geo.ProximityAllowed, true},
		{750.0, geo.ProximityAllowed, true},
		{999.0, geo.ProximityAllowed, true},
		{999.9, geo.ProximityAllowed, true},
		{1000.0, geo.ProximityAllowed, true},
		{1000.1, geo.ProximityOutsideRadius, false},
		{1001.0, geo.ProximityOutsideRadius, false},
		{1500.0, geo.ProximityOutsideRadius, false},
		{5000.0, geo.ProximityOutsideRadius, false},
	}

	for _, tc := range cases {
		t.Run(fmt.Sprintf("%.1fm", tc.distMeters), func(t *testing.T) {
			locA := &geo.LocationData{
				UserID:         "user-a",
				Latitude:       baseLat,
				Longitude:      baseLon,
				AccuracyMeters: 10.0,
				UpdatedAt:      now,
			}
			locB := &geo.LocationData{
				UserID:         "user-b",
				Latitude:       baseLat + offsetLatForDistance(tc.distMeters),
				Longitude:      baseLon,
				AccuracyMeters: 10.0,
				UpdatedAt:      now,
			}

			res := geo.EvaluateProximity(locA, locB, now)
			if res.Allowed != tc.allowed {
				t.Fatalf("expected allowed=%v, got %v (status=%s, dist=%f)", tc.allowed, res.Allowed, res.Status, res.DistanceMeters)
			}
			if res.Status != tc.expectedCode {
				t.Fatalf("expected status=%s, got %s", tc.expectedCode, res.Status)
			}
		})
	}
}

func TestProximityValidator_StaleAndAccuracy(t *testing.T) {
	now := time.Now().UTC()
	baseLat := 17.440081
	baseLon := 78.348916

	// Fresh and accurate -> ALLOW
	locA := &geo.LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 15.0, UpdatedAt: now}
	locB := &geo.LocationData{UserID: "b", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 20.0, UpdatedAt: now}
	res := geo.EvaluateProximity(locA, locB, now)
	if !res.Allowed {
		t.Fatalf("expected ALLOW for fresh & accurate, got %s", res.Status)
	}

	// Stale A (updated 75 seconds ago) -> STALE_LOCATION
	locAStale := &geo.LocationData{UserID: "a", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 15.0, UpdatedAt: now.Add(-75 * time.Second)}
	resStale := geo.EvaluateProximity(locAStale, locB, now)
	if resStale.Allowed || resStale.Status != geo.ProximityStaleLocation {
		t.Fatalf("expected STALE_LOCATION, got %s (allowed=%v)", resStale.Status, resStale.Allowed)
	}

	// Poor accuracy B (accuracy = 85m > 50m limit) -> POOR_ACCURACY
	locBPoor := &geo.LocationData{UserID: "b", Latitude: baseLat, Longitude: baseLon, AccuracyMeters: 85.0, UpdatedAt: now}
	resPoor := geo.EvaluateProximity(locA, locBPoor, now)
	if resPoor.Allowed || resPoor.Status != geo.ProximityPoorAccuracy {
		t.Fatalf("expected POOR_ACCURACY, got %s (allowed=%v)", resPoor.Status, resPoor.Allowed)
	}
}

func TestProximityValidator_Serialization(t *testing.T) {
	loc := geo.LocationData{
		UserID:         "user-123",
		Latitude:       17.44,
		Longitude:      78.34,
		AccuracyMeters: 8.5,
		UpdatedAt:      time.Now().UTC(),
	}

	data, err := json.Marshal(&loc)
	if err != nil {
		t.Fatalf("marshal error: %v", err)
	}

	var decoded geo.LocationData
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}

	if decoded.UserID != loc.UserID || decoded.Latitude != loc.Latitude || decoded.Longitude != loc.Longitude {
		t.Fatalf("decoded data mismatch: %+v vs %+v", decoded, loc)
	}
}
