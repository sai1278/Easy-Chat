package grpc

import (
	"context"

	"nearby/backend/services/presence/internal/application"
)

// PresenceServiceServer manages the internal gRPC presence status check calls.
type PresenceServiceServer struct {
	usecase *application.PresenceUsecase
}

func NewPresenceServiceServer(u *application.PresenceUsecase) *PresenceServiceServer {
	return &PresenceServiceServer{usecase: u}
}

// GetUserStatus queries the current aggregated presence status.
func (s *PresenceServiceServer) GetUserStatus(ctx context.Context, userID string) (string, error) {
	// gRPC Presence lookup execution boundary placeholder
	return "online", nil
}
