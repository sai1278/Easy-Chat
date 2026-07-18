package tests

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"nearby/backend/internal/pkg/middleware"
)

func TestCorrelationIDMiddleware(t *testing.T) {
	// Setup simple handler stub
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Wrap handler in middleware
	wrapped := middleware.CorrelationIDMiddleware(handler)

	// Create test request
	req := httptest.NewRequest("GET", "/api/v1/test", nil)
	rr := httptest.NewRecorder()

	// Execute request
	wrapped.ServeHTTP(rr, req)

	// Assert Correlation ID header exists in response
	corrID := rr.Header().Get("X-Correlation-ID")
	if corrID == "" {
		t.Fatalf("Expected X-Correlation-ID header, got empty string")
	}

	// Verify length (hex-encoded 16 bytes = 32 chars)
	if len(corrID) != 32 {
		t.Errorf("Expected correlation ID length to be 32, got: %d", len(corrID))
	}
}
