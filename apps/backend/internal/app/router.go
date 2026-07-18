package app

import (
	"net/http"

	"nearby/backend/internal/pkg/idempotency"
	"nearby/backend/internal/pkg/middleware"
)

// Router orchestrates the middleware chains and route registrations.
type Router struct {
	mux         *http.ServeMux
	idempEngine *idempotency.Engine
}

func NewRouter(engine *idempotency.Engine) *Router {
	return &Router{
		mux:         http.NewServeMux(),
		idempEngine: engine,
	}
}

// RegisterRoutes links endpoints to handlers wrapping global middlewares.
func (r *Router) RegisterRoutes(authH *AuthHandler, userH *UserHandler, proxH *ProximityHandler) http.Handler {
	
	// Create middleware wrappers
	idempMw := middleware.IdempotencyMiddleware(r.idempEngine)

	// Define routes matching the API specification
	r.mux.Handle("POST /api/v1/auth/session", idempMw(http.HandlerFunc(authH.Onboard)))
	r.mux.Handle("PATCH /api/v1/users/me", idempMw(http.HandlerFunc(userH.UpdateProfile)))
	r.mux.Handle("POST /api/v1/visibility/toggle", idempMw(http.HandlerFunc(proxH.ToggleVisibility)))

	// Compose global middleware pipeline
	var pipeline http.Handler = r.mux
	pipeline = middleware.RecoveryMiddleware(pipeline)
	pipeline = middleware.RequestLogger(pipeline)
	pipeline = middleware.CorrelationIDMiddleware(pipeline)

	return pipeline
}
