package http

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func generateTestTokenWithExp(userID, role string, secretKey []byte, exp time.Time) string {
	claims := jwt.MapClaims{
		"sub":  userID,
		"sid":  "sess_1",
		"role": role,
		"exp":  exp.Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, _ := token.SignedString(secretKey)
	return tokenStr
}

func TestAdversarial_UnauthenticatedAccess(t *testing.T) {
	secretKey := []byte("production-hmac-signing-key-12345")
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
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
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// Generate a valid token
	validToken := generateTestTokenWithExp("user_123", "user", secretKey, time.Now().Add(15*time.Minute))
	
	// Tamper the token signature by replacing the last few characters
	tamperedToken := validToken + "tampered"

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
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// Expired token (10 minutes ago)
	expiredToken := generateTestTokenWithExp("user_123", "user", secretKey, time.Now().Add(-10*time.Minute))

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
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
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
