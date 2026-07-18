package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"nearby/backend/services/nearby/internal/domain"
)

type mockUserRepository struct {
	activeMetadata map[string]*domain.UserMetadata
	blockFilter    map[string]bool
	metadataErr    error
	blockErr       error
}

func (m *mockUserRepository) GetActiveUsersMetadata(ctx context.Context, userIDs []string) (map[string]*domain.UserMetadata, error) {
	if m.metadataErr != nil {
		return nil, m.metadataErr
	}
	res := make(map[string]*domain.UserMetadata)
	for _, id := range userIDs {
		if meta, ok := m.activeMetadata[id]; ok {
			res[id] = meta
		}
	}
	return res, nil
}

func (m *mockUserRepository) GetBlockFilter(ctx context.Context, userID string) (map[string]bool, error) {
	if m.blockErr != nil {
		return nil, m.blockErr
	}
	return m.blockFilter, nil
}

type mockGeoRepository struct {
	locations       map[string][]float64 // userID -> [lat, lon]
	nearbyIDs       []string
	distances       map[string]float64
	throttleAllowed bool
	updateCalled    bool
	updateErr       error
	removeErr       error
	findErr         error
	throttleErr     error
}

func (m *mockGeoRepository) UpdateUserLocation(ctx context.Context, userID string, lat, lon float64, ttl time.Duration) error {
	m.updateCalled = true
	if m.updateErr != nil {
		return m.updateErr
	}
	if m.locations == nil {
		m.locations = make(map[string][]float64)
	}
	m.locations[userID] = []float64{lat, lon}
	return nil
}

func (m *mockGeoRepository) RemoveUserLocation(ctx context.Context, userID string) error {
	if m.removeErr != nil {
		return m.removeErr
	}
	delete(m.locations, userID)
	return nil
}

func (m *mockGeoRepository) FindNearbyUsers(ctx context.Context, lat, lon float64, radiusMeters int) ([]string, map[string]float64, error) {
	if m.findErr != nil {
		return nil, nil, m.findErr
	}
	return m.nearbyIDs, m.distances, nil
}

func (m *mockGeoRepository) CheckThrottling(ctx context.Context, userID string, limit int, window time.Duration) (bool, error) {
	if m.throttleErr != nil {
		return false, m.throttleErr
	}
	return m.throttleAllowed, nil
}

func TestFindNearby_Success(t *testing.T) {
	userRepo := &mockUserRepository{
		activeMetadata: map[string]*domain.UserMetadata{
			"requester": {UserID: "requester", Pseudonym: "alpha user", AvatarID: 1, Status: "ACTIVE", IsVisible: true},
			"user1":     {UserID: "user1", Pseudonym: "crimson shadow", AvatarID: 5, Status: "ACTIVE", IsVisible: true},
			"user2":     {UserID: "user2", Pseudonym: "silver fox", AvatarID: 10, Status: "ACTIVE", IsVisible: true},
		},
		blockFilter: map[string]bool{},
	}

	geoRepo := &mockGeoRepository{
		locations:       make(map[string][]float64),
		nearbyIDs:       []string{"requester", "user1", "user2"},
		distances:       map[string]float64{"requester": 0.0, "user1": 75.0, "user2": 150.0},
		throttleAllowed: true,
	}

	usecase := NewNearbyUsecase(userRepo, geoRepo)

	ctx := context.Background()
	results, err := usecase.FindNearby(ctx, "requester", 10.0, 20.0, 200, 10, time.Minute)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if !geoRepo.updateCalled {
		t.Error("Expected requester location to be published, but it was not")
	}

	if len(results) != 2 {
		t.Fatalf("Expected 2 nearby users, got %d", len(results))
	}

	// Verify distances and bucketing
	if results[0].UserID != "user1" || results[0].DistanceBucket != "within 100m" {
		t.Errorf("Unexpected user1 results: %+v", results[0])
	}
	if results[1].UserID != "user2" || results[1].DistanceBucket != "within 200m" {
		t.Errorf("Unexpected user2 results: %+v", results[1])
	}
}

func TestFindNearby_Throttling(t *testing.T) {
	userRepo := &mockUserRepository{}
	geoRepo := &mockGeoRepository{
		throttleAllowed: false,
	}

	usecase := NewNearbyUsecase(userRepo, geoRepo)

	ctx := context.Background()
	_, err := usecase.FindNearby(ctx, "requester", 10.0, 20.0, 200, 10, time.Minute)
	if !errors.Is(err, ErrRateLimitExceeded) {
		t.Fatalf("Expected ErrRateLimitExceeded, got %v", err)
	}
}

func TestFindNearby_BlockFiltering(t *testing.T) {
	userRepo := &mockUserRepository{
		activeMetadata: map[string]*domain.UserMetadata{
			"requester": {UserID: "requester", Pseudonym: "alpha user", AvatarID: 1, Status: "ACTIVE", IsVisible: true},
			"user1":     {UserID: "user1", Pseudonym: "crimson shadow", AvatarID: 5, Status: "ACTIVE", IsVisible: true},
			"user2":     {UserID: "user2", Pseudonym: "silver fox", AvatarID: 10, Status: "ACTIVE", IsVisible: true},
		},
		blockFilter: map[string]bool{
			"user1": true, // user1 is blocked (or blocks requester)
		},
	}

	geoRepo := &mockGeoRepository{
		nearbyIDs:       []string{"requester", "user1", "user2"},
		distances:       map[string]float64{"requester": 0.0, "user1": 70.0, "user2": 130.0},
		throttleAllowed: true,
	}

	usecase := NewNearbyUsecase(userRepo, geoRepo)

	ctx := context.Background()
	results, err := usecase.FindNearby(ctx, "requester", 10.0, 20.0, 200, 10, time.Minute)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("Expected 1 nearby user (user1 filtered out), got %d", len(results))
	}

	if results[0].UserID != "user2" {
		t.Errorf("Expected user2, got %s", results[0].UserID)
	}
}

func TestFindNearby_InactiveAndInvisible(t *testing.T) {
	userRepo := &mockUserRepository{
		activeMetadata: map[string]*domain.UserMetadata{
			"requester": {UserID: "requester", Pseudonym: "alpha user", AvatarID: 1, Status: "ACTIVE", IsVisible: true},
			// user1 is missing from metadata because they are suspended or invisible (filtered by SQL query)
			"user2": {UserID: "user2", Pseudonym: "silver fox", AvatarID: 10, Status: "ACTIVE", IsVisible: true},
		},
		blockFilter: map[string]bool{},
	}

	geoRepo := &mockGeoRepository{
		nearbyIDs:       []string{"requester", "user1", "user2"},
		distances:       map[string]float64{"requester": 0.0, "user1": 70.0, "user2": 130.0},
		throttleAllowed: true,
	}

	usecase := NewNearbyUsecase(userRepo, geoRepo)

	ctx := context.Background()
	results, err := usecase.FindNearby(ctx, "requester", 10.0, 20.0, 200, 10, time.Minute)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("Expected 1 user (user1 filtered), got %d", len(results))
	}

	if results[0].UserID != "user2" {
		t.Errorf("Expected user2, got %s", results[0].UserID)
	}
}
