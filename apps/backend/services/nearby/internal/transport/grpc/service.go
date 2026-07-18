package grpc

import (
	"context"
	"errors"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	genv1 "nearby/backend/internal/gen/v1"
	"nearby/backend/services/nearby/internal/application"
	"nearby/backend/services/nearby/internal/pkg/h3"
)

// NearbyServiceServer implements the generated gRPC NearbyServiceServer interface.
type NearbyServiceServer struct {
	genv1.UnimplementedNearbyServiceServer
	usecase *application.NearbyUsecase
}

// NewNearbyServiceServer creates a new NearbyServiceServer.
func NewNearbyServiceServer(usecase *application.NearbyUsecase) *NearbyServiceServer {
	return &NearbyServiceServer{usecase: usecase}
}

// GetNearbyUsers processes nearby discovery requests, decoding H3 coordinates and validating parameters.
func (s *NearbyServiceServer) GetNearbyUsers(ctx context.Context, req *genv1.GetNearbyUsersRequest) (*genv1.GetNearbyUsersResponse, error) {
	userID := req.GetUserId()
	h3IndexStr := req.GetH3Index()
	radiusMeters := req.GetRadiusMeters()

	// 1. Parameter Validation
	if userID == "" {
		return nil, status.Error(codes.InvalidArgument, "user_id is required")
	}
	if h3IndexStr == "" {
		return nil, status.Error(codes.InvalidArgument, "h3_index is required")
	}
	if radiusMeters < 100 || radiusMeters > 200 {
		return nil, status.Error(codes.InvalidArgument, "radius must be between 100 and 200 meters")
	}

	// 2. Parse H3 Index and convert to Latitude/Longitude
	lat, lon, err := h3.ToLatLng(h3IndexStr)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid H3 coordinate index format: %v", err)
	}

	// 3. Run search use case (anti-spam set to 10 requests per 60 seconds)
	throttleLimit := 10
	throttleWindow := 60 * time.Second

	nearbyUsers, err := s.usecase.FindNearby(ctx, userID, lat, lon, int(radiusMeters), throttleLimit, throttleWindow)
	if err != nil {
		if errors.Is(err, application.ErrRateLimitExceeded) {
			return nil, status.Error(codes.ResourceExhausted, "request limit exceeded; please slow down")
		}
		return nil, status.Errorf(codes.Internal, "failed to find nearby users: %v", err)
	}

	// 4. Format responses
	protoUsers := make([]*genv1.NearbyUser, 0, len(nearbyUsers))
	for _, u := range nearbyUsers {
		protoUsers = append(protoUsers, &genv1.NearbyUser{
			UserId:         u.UserID,
			Pseudonym:      u.Pseudonym,
			AvatarId:       u.AvatarID,
			DistanceBucket: u.DistanceBucket,
		})
	}

	return &genv1.GetNearbyUsersResponse{
		Users: protoUsers,
	}, nil
}
