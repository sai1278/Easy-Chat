package security

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	gateway "nearby/backend/services/gateway/internal/transport/http"
)

func TestAdversarial_UnauthenticatedAccess(t *testing.T) {
	secretKey := []byte("production-hmac-signing-key-12345")
	router := gateway.NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// 1. Attempt unauthenticated call
	req := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized, got %d", w.Code)
	}
}

func TestAdversarial_JWT_Tampering(t *testing.T) {
	secretKey := []byte("production-hmac-signing-key-12345")
	router := gateway.NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// Generate a token
	payload := `{"sub":"user_123","role":"user","exp":32503680000}` // Exp in far future
	h := sha256.New()
	h.Write([]byte(payload + string(secretKey)))
	sig := hex.EncodeToString(h.Sum(nil))
	
	// Tamper payload content (modify User ID)
	tamperedPayload := `{"sub":"user_admin_spoof","role":"admin","exp":32503680000}`
	tamperedToken := fmt.Sprintf("eyJhbGciOiJSUzI1NiJ9.%s.%s", tamperedPayload, sig)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	req.Header.Set("Authorization", "Bearer "+tamperedToken)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for tampered JWT, got %d", w.Code)
	}
}

func TestAdversarial_JWT_Expiration(t *testing.T) {
	secretKey := []byte("production-hmac-signing-key-12345")
	router := gateway.NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// Expired payload
	expiredTime := time.Now().Add(-10 * time.Minute).Unix()
	payload := fmt.Sprintf(`{"sub":"user_123","role":"user","exp":%d}`, expiredTime)
	h := sha256.New()
	h.Write([]byte(payload + string(secretKey)))
	sig := hex.EncodeToString(h.Sum(nil))
	expiredToken := fmt.Sprintf("eyJhbGciOiJSUzI1NiJ9.%s.%s", payload, sig)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	req.Header.Set("Authorization", "Bearer "+expiredToken)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for expired token, got %d", w.Code)
	}
}

func TestAdversarial_RateLimit_Enforcement(t *testing.T) {
	secretKey := []byte("production-hmac-signing-key-12345")
	router := gateway.NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// Send rapid requests to exceed the limit (burst limit is 20)
	var triggered bool
	for i := 0; i < 25; i++ {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		req.RemoteAddr = "10.0.0.1:1234"
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
		if w.Code == http.StatusTooManyRequests {
			triggered = true
			break
		}
	}

	if !triggered {
		t.Error("expected rate limiter to trigger HTTP 429 after exceeding thresholds")
	}
}
