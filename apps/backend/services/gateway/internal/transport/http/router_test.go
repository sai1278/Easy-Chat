package http

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func generateTestToken(userID, role string, secretKey []byte) string {
	claims := jwt.MapClaims{
		"sub":  userID,
		"sid":  "sess_1",
		"role": role,
		"exp":  time.Now().Add(15 * time.Minute).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, _ := token.SignedString(secretKey)
	return tokenStr
}

func TestRouter_RequestIDAndSecurityHeaders(t *testing.T) {
	secretKey := []byte("test_secret")
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	// Verify Request ID
	reqID := w.Header().Get("X-Request-ID")
	if reqID == "" {
		t.Error("expected X-Request-ID response header to be injected")
	}

	// Verify Security Headers
	if w.Header().Get("X-Frame-Options") != "DENY" {
		t.Error("missing or invalid X-Frame-Options header")
	}
	if w.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Error("missing or invalid X-Content-Type-Options header")
	}
	if !strings.Contains(w.Header().Get("Strict-Transport-Security"), "max-age") {
		t.Error("missing or invalid Strict-Transport-Security header")
	}
}

func TestRouter_RateLimiting(t *testing.T) {
	secretKey := []byte("test_secret")
	router := NewRouter(secretKey, []string{}, []string{}, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// The rate limiter allows a burst of 20. Send 22 requests from the same IP client rapidly.
	var hit429 bool
	for i := 0; i < 25; i++ {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		req.RemoteAddr = "127.0.0.1:1234"
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)

		if w.Code == http.StatusTooManyRequests {
			hit429 = true
			break
		}
	}

	if !hit429 {
		t.Error("expected rate limiter to trigger HTTP 429 after exceeding burst threshold")
	}
}

func TestRouter_AuthValidation(t *testing.T) {
	secretKey := []byte("test_secret")
	
	// Create mock backend user service
	var receivedUserID, receivedUserRole string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedUserID = r.Header.Get("X-User-Id")
		receivedUserRole = r.Header.Get("X-User-Role")
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	router := NewRouter(secretKey, []string{}, []string{backend.URL}, []string{}, []string{}, []string{}, []string{}, []string{})
	handler := router.RegisterRoutes()

	// 1. Request without token
	reqNoToken := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	wNoToken := httptest.NewRecorder()
	handler.ServeHTTP(wNoToken, reqNoToken)
	if wNoToken.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized without token, got %d", wNoToken.Code)
	}

	// 2. Request with invalid token
	reqBadToken := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	reqBadToken.Header.Set("Authorization", "Bearer bad.token.signature")
	wBadToken := httptest.NewRecorder()
	handler.ServeHTTP(wBadToken, reqBadToken)
	if wBadToken.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized with invalid token, got %d", wBadToken.Code)
	}

	// 3. Request with valid token
	userID := "user_abc"
	role := "admin"
	
	validToken := generateTestToken(userID, role, secretKey)

	reqValidToken := httptest.NewRequest(http.MethodGet, "/api/v1/user/profile", nil)
	reqValidToken.Header.Set("Authorization", "Bearer "+validToken)
	wValidToken := httptest.NewRecorder()
	
	handler.ServeHTTP(wValidToken, reqValidToken)
	if wValidToken.Code != http.StatusOK {
		t.Errorf("expected 200 OK with valid token, got %d", wValidToken.Code)
	}

	// Verify claims were injected into headers forwarded to the backend service
	if receivedUserID != userID {
		t.Errorf("expected forwarded User ID %s, got %s", userID, receivedUserID)
	}
	if receivedUserRole != role {
		t.Errorf("expected forwarded User Role %s, got %s", role, receivedUserRole)
	}
}

func TestRouter_CircuitBreaker(t *testing.T) {
	secretKey := []byte("test_secret")

	// Create mock failing backend user service
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer backend.Close()

	router := NewRouter(secretKey, []string{}, []string{backend.URL}, []string{}, []string{}, []string{}, []string{}, []string{})
	
	// Fast track tests bypass auth for ease
	router.mux.HandleFunc("/api/v1/user/test-cb", router.ProxyHandler(router.userCluster, router.userCB))
	handler := router.RegisterRoutes()

	// Generate valid token
	validToken := generateTestToken("user_cb", "user", secretKey)

	// Send 5 failing requests to trip the circuit breaker
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/user/test-cb", nil)
		req.Header.Set("Authorization", "Bearer "+validToken)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
		if w.Code != http.StatusInternalServerError {
			t.Fatalf("expected 500 error, got %d", w.Code)
		}
	}

	// The 6th request should fail with 503 (Service Unavailable) due to tripped circuit breaker
	reqTripped := httptest.NewRequest(http.MethodGet, "/api/v1/user/test-cb", nil)
	reqTripped.Header.Set("Authorization", "Bearer "+validToken)
	wTripped := httptest.NewRecorder()
	handler.ServeHTTP(wTripped, reqTripped)

	if wTripped.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503 Service Unavailable, got %d", wTripped.Code)
	}
	if !strings.Contains(wTripped.Body.String(), "circuit breaker is open") {
		t.Errorf("expected circuit breaker error message, got %s", wTripped.Body.String())
	}
}

func TestRouter_LoadBalancing(t *testing.T) {
	secretKey := []byte("test_secret")

	var server1Hits, server2Hits int32

	backend1 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&server1Hits, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer backend1.Close()

	backend2 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&server2Hits, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer backend2.Close()

	router := NewRouter(secretKey, []string{}, []string{backend1.URL, backend2.URL}, []string{}, []string{}, []string{}, []string{}, []string{})
	router.mux.HandleFunc("/api/v1/user/test-lb", router.ProxyHandler(router.userCluster, router.userCB))
	handler := router.RegisterRoutes()

	// Generate valid token
	validToken := generateTestToken("user_lb", "user", secretKey)

	// Make 4 requests
	for i := 0; i < 4; i++ {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/user/test-lb", nil)
		req.Header.Set("Authorization", "Bearer "+validToken)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
	}

	// Verify round-robin load balancing (each target hit twice)
	if atomic.LoadInt32(&server1Hits) != 2 || atomic.LoadInt32(&server2Hits) != 2 {
		t.Errorf("expected round robin distribution (2 each), got Server1: %d, Server2: %d", server1Hits, server2Hits)
	}
}

func TestRouter_RequestSizeProtection(t *testing.T) {
	secretKey := []byte("test_secret")
	
	// Create mock backend
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, err := io.Copy(io.Discard, r.Body)
		if err != nil {
			if strings.Contains(err.Error(), "request body too large") {
				w.WriteHeader(http.StatusRequestEntityTooLarge)
				return
			}
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	router := NewRouter(secretKey, []string{}, []string{backend.URL}, []string{}, []string{}, []string{}, []string{}, []string{})
	router.mux.HandleFunc("/api/v1/user/test-limit", router.ProxyHandler(router.userCluster, router.userCB))
	handler := router.RegisterRoutes()

	// Generate valid token
	validToken := generateTestToken("user_limit", "user", secretKey)

	// 1. Oversized content-length request (> 10MB)
	largeBody := strings.Repeat("a", 11*1024*1024) // 11MB
	reqLarge := httptest.NewRequest(http.MethodPost, "/api/v1/user/test-limit", strings.NewReader(largeBody))
	reqLarge.Header.Set("Authorization", "Bearer "+validToken)
	wLarge := httptest.NewRecorder()
	handler.ServeHTTP(wLarge, reqLarge)
	if wLarge.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("expected 413 Payload Too Large, got %d", wLarge.Code)
	}

	// 2. Chunked encoding request exceeding limit
	reqChunked := httptest.NewRequest(http.MethodPost, "/api/v1/user/test-limit", strings.NewReader(largeBody))
	reqChunked.Header.Set("Authorization", "Bearer "+validToken)
	reqChunked.TransferEncoding = []string{"chunked"}
	reqChunked.ContentLength = -1
	wChunked := httptest.NewRecorder()
	handler.ServeHTTP(wChunked, reqChunked)
	if wChunked.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("expected 413 Payload Too Large for chunked over limit, got %d", wChunked.Code)
	}

	// 3. Valid request under limit
	smallBody := "hello world"
	reqSmall := httptest.NewRequest(http.MethodPost, "/api/v1/user/test-limit", strings.NewReader(smallBody))
	reqSmall.Header.Set("Authorization", "Bearer "+validToken)
	wSmall := httptest.NewRecorder()
	handler.ServeHTTP(wSmall, reqSmall)
	if wSmall.Code != http.StatusOK {
		t.Errorf("expected 200 OK for small request, got %d", wSmall.Code)
	}
}
