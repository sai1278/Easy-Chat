package http

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/golang-jwt/jwt/v5"
	gocache "github.com/patrickmn/go-cache"
	"golang.org/x/time/rate"
	"nearby/backend/shared/logger"
)

// CircuitBreaker tracks routing success/failure states to prevent backend overloading.
type CircuitBreaker struct {
	mu           sync.Mutex
	state        string // "CLOSED", "OPEN", "HALF-OPEN"
	failureCount int
	successCount int
	threshold    int
	openUntil    time.Time
	cooldown     time.Duration
}

// NewCircuitBreaker creates a new CircuitBreaker.
func NewCircuitBreaker(threshold int, cooldown time.Duration) *CircuitBreaker {
	return &CircuitBreaker{
		state:     "CLOSED",
		threshold: threshold,
		cooldown:  cooldown,
	}
}

// Allow returns true if the circuit breaker allows the request to pass.
func (cb *CircuitBreaker) Allow() bool {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	if cb.state == "OPEN" {
		if time.Now().After(cb.openUntil) {
			cb.state = "HALF-OPEN"
			cb.failureCount = 0
			cb.successCount = 0
			return true
		}
		return false
	}
	return true
}

// OnSuccess registers a successful backend proxy transaction.
func (cb *CircuitBreaker) OnSuccess() {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	if cb.state == "HALF-OPEN" {
		cb.successCount++
		if cb.successCount >= 3 {
			cb.state = "CLOSED"
			cb.failureCount = 0
		}
	}
}

// OnFailure registers a failed backend proxy transaction (HTTP 5xx).
func (cb *CircuitBreaker) OnFailure() {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	cb.failureCount++
	if cb.state == "CLOSED" {
		if cb.failureCount >= cb.threshold {
			cb.state = "OPEN"
			cb.openUntil = time.Now().Add(cb.cooldown)
		}
	} else if cb.state == "HALF-OPEN" {
		cb.state = "OPEN"
		cb.openUntil = time.Now().Add(cb.cooldown)
	}
}

// LoadBalancer performs atomic round-robin server routing.
type LoadBalancer struct {
	hosts []string
	index uint64
}

// NewLoadBalancer creates a new LoadBalancer.
func NewLoadBalancer(hosts []string) *LoadBalancer {
	return &LoadBalancer{hosts: hosts}
}

// Next selects the next server host using atomic round-robin.
// Returns an empty string and logs an error when the host slice is empty (HIGH-02).
func (lb *LoadBalancer) Next() (string, error) {
	if len(lb.hosts) == 0 {
		return "", errors.New("load balancer: no upstream hosts configured")
	}
	idx := atomic.AddUint64(&lb.index, 1)
	return lb.hosts[idx%uint64(len(lb.hosts))], nil
}

// IPRateLimiter maps client IPs to per-IP rate limiters with automatic TTL eviction.
// Backed by go-cache to prevent unbounded map growth (HIGH-01).
type IPRateLimiter struct {
	cache *gocache.Cache
}

// NewIPRateLimiter creates a new IPRateLimiter with 10-minute TTL and 1-minute cleanup interval.
func NewIPRateLimiter() *IPRateLimiter {
	return &IPRateLimiter{
		cache: gocache.New(10*time.Minute, 1*time.Minute),
	}
}

// GetLimiter returns the IP-bound rate limiter, creating one on first access.
// Idle IPs are evicted after 10 minutes, preventing memory leaks.
func (l *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	if v, ok := l.cache.Get(ip); ok {
		l.cache.Set(ip, v, gocache.DefaultExpiration) // refresh TTL on access
		return v.(*rate.Limiter)
	}
	lim := rate.NewLimiter(rate.Limit(10.0), 20) // 10 reqs/sec, burst of 20
	l.cache.Set(ip, lim, gocache.DefaultExpiration)
	return lim
}

// ResponseRecorder captures HTTP status codes returned by proxy.
type ResponseRecorder struct {
	http.ResponseWriter
	Status int
}

func (r *ResponseRecorder) WriteHeader(statusCode int) {
	r.Status = statusCode
	r.ResponseWriter.WriteHeader(statusCode)
}

func (r *ResponseRecorder) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hj, ok := r.ResponseWriter.(http.Hijacker); ok {
		return hj.Hijack()
	}
	return nil, nil, fmt.Errorf("underlying ResponseWriter does not implement http.Hijacker")
}

// Router configures microservice upstreams, middleware, and request multiplexing.
type Router struct {
	mux               *http.ServeMux
	secretKey         []byte
	limiter           *IPRateLimiter
	authCluster       *LoadBalancer
	userCluster       *LoadBalancer
	chatCluster       *LoadBalancer
	nearbyCluster     *LoadBalancer
	presCluster       *LoadBalancer
	mediaCluster      *LoadBalancer
	complianceCluster *LoadBalancer
	authCB            *CircuitBreaker
	userCB            *CircuitBreaker
	chatCB            *CircuitBreaker
	nearbyCB          *CircuitBreaker
	presCB            *CircuitBreaker
	mediaCB           *CircuitBreaker
	complianceCB      *CircuitBreaker
	jwksURL           string
	issuer            string
	// jwksCache holds verified public keys keyed by KID. Keys are evicted and
	// replaced on every JWKS refresh, preventing stale keys after rotation (CRIT-14).
	jwksCache   *gocache.Cache
	cacheMutex  sync.RWMutex
	lastFetched time.Time
}

// NewRouter initializes proxies, circuit breakers, and rate limiters.
func NewRouter(secretKey []byte, authHosts, userHosts, chatHosts, nearbyHosts, presHosts, mediaHosts, complianceHosts []string) *Router {
	return &Router{
		mux:               http.NewServeMux(),
		secretKey:         secretKey,
		limiter:           NewIPRateLimiter(),
		authCluster:       NewLoadBalancer(authHosts),
		userCluster:       NewLoadBalancer(userHosts),
		chatCluster:       NewLoadBalancer(chatHosts),
		nearbyCluster:     NewLoadBalancer(nearbyHosts),
		presCluster:       NewLoadBalancer(presHosts),
		mediaCluster:      NewLoadBalancer(mediaHosts),
		complianceCluster: NewLoadBalancer(complianceHosts),
		authCB:            NewCircuitBreaker(5, 10*time.Second),
		userCB:            NewCircuitBreaker(5, 10*time.Second),
		chatCB:            NewCircuitBreaker(5, 10*time.Second),
		nearbyCB:          NewCircuitBreaker(5, 10*time.Second),
		presCB:            NewCircuitBreaker(5, 10*time.Second),
		mediaCB:           NewCircuitBreaker(5, 10*time.Second),
		complianceCB:      NewCircuitBreaker(5, 10*time.Second),
		jwksURL:           "http://keycloak-service.default.svc.cluster.local:8080/realms/easychat/protocol/openid-connect/certs",
		issuer:            "http://keycloak-service.default.svc.cluster.local:8080/realms/easychat",
		// 15-minute key TTL with 5-minute cleanup. Shorter than key rotation cycles.
		jwksCache: gocache.New(15*time.Minute, 5*time.Minute),
	}
}

// RegisterRoutes registers URL paths mapping to clusters.
func (r *Router) RegisterRoutes() http.Handler {
	// Base health endpoint
	r.mux.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	r.mux.HandleFunc("/health", func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Register cluster proxy route handlers
	r.mux.HandleFunc("/api/v1/auth/", r.ProxyHandler(r.authCluster, r.authCB))
	r.mux.HandleFunc("/api/v1/user/", r.ProxyHandler(r.userCluster, r.userCB))
	r.mux.HandleFunc("/api/v1/chat/", r.ProxyHandler(r.chatCluster, r.chatCB))
	r.mux.HandleFunc("/api/v1/nearby/", r.ProxyHandler(r.nearbyCluster, r.nearbyCB))
	r.mux.HandleFunc("/api/v1/presence/", r.ProxyHandler(r.presCluster, r.presCB))
	r.mux.HandleFunc("/api/v1/media/", r.ProxyHandler(r.mediaCluster, r.mediaCB))
	r.mux.HandleFunc("/api/v1/compliance/", r.ProxyHandler(r.complianceCluster, r.complianceCB))
	r.mux.HandleFunc("/ws", r.ProxyHandler(r.chatCluster, r.chatCB))

	// Chain middlewares: Correlation/Logging -> Cors -> Security Headers -> Gzip -> Rate Limiting -> Auth -> Request Validation -> Router Mux
	handler := r.RequestValidationMiddleware(r.mux)
	handler = r.AuthValidationMiddleware(handler)
	handler = r.RateLimitMiddleware(handler)
	handler = r.GzipCompressionMiddleware(handler)
	handler = r.SecurityHeadersMiddleware(handler)
	handler = r.CorsMiddleware(handler)
	handler = r.LoggingAndRequestIDMiddleware(handler)

	return handler
}

// CorsMiddleware handles Cross-Origin Resource Sharing (CORS) preflight OPTIONS requests and sets headers.
func (r *Router) CorsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		origin := req.Header.Get("Origin")
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Accept, X-Request-Id, Idempotency-Key, Upgrade, Connection")
		w.Header().Set("Access-Control-Max-Age", "86400")

		if req.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, req)
	})
}

// ProxyHandler performs reverse proxying with round-robin balancing and circuit breakers.
func (r *Router) ProxyHandler(lb *LoadBalancer, cb *CircuitBreaker) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		if !cb.Allow() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error":"Service unavailable: circuit breaker is open"}`))
			return
		}

		// Guard against empty host list (HIGH-02).
		targetHost, err := lb.Next()
		if err != nil {
			slog.Error("Load balancer: no upstream hosts", "error", err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error":"Service unavailable: no upstream hosts configured"}`))
			return
		}
		targetURL, err := url.Parse(targetHost)
		if err != nil {
			cb.OnFailure()
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		proxy := httputil.NewSingleHostReverseProxy(targetURL)
		proxy.ErrorHandler = func(rw http.ResponseWriter, req *http.Request, err error) {
			if err != nil && (strings.Contains(err.Error(), "request body too large") || strings.Contains(err.Error(), "limit exceeded")) {
				rw.Header().Set("Content-Type", "application/json")
				rw.WriteHeader(http.StatusRequestEntityTooLarge)
				_, _ = rw.Write([]byte(`{"error":"Payload too large: maximum 10MB allowed"}`))
				return
			}
			rw.WriteHeader(http.StatusBadGateway)
		}



		// Set forwarding headers
		req.URL.Host = targetURL.Host
		req.URL.Scheme = targetURL.Scheme
		req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
		req.Host = targetURL.Host

		// Inject downstream correlation/request id
		if corrID, ok := req.Context().Value(logger.CorrelationIDKey).(string); ok {
			req.Header.Set("X-Request-ID", corrID)
		}

		isWebSocket := strings.ToLower(req.Header.Get("Upgrade")) == "websocket" || req.URL.Path == "/ws"
		if isWebSocket {
			proxy.ServeHTTP(w, req)
			cb.OnSuccess()
		} else {
			recorder := &ResponseRecorder{ResponseWriter: w, Status: http.StatusOK}
			proxy.ServeHTTP(recorder, req)

			if recorder.Status >= 500 {
				cb.OnFailure()
			} else {
				cb.OnSuccess()
			}
		}
	}
}

// Middleware 1: Request Validation
func (r *Router) RequestValidationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// Restrict request size (max 10MB) to mitigate buffer-bloat / DDoS
		if req.ContentLength > 10*1024*1024 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusRequestEntityTooLarge)
			_, _ = w.Write([]byte(`{"error":"Payload too large: maximum 10MB allowed"}`))
			return
		}
		
		// Enforce body size limit using MaxBytesReader to catch chunked encoding bypasses
		req.Body = http.MaxBytesReader(w, req.Body, 10*1024*1024)
		
		next.ServeHTTP(w, req)
	})
}

// Middleware 2: IP-bound Rate Limiter
func (r *Router) RateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ip := req.RemoteAddr
		if colon := strings.LastIndex(ip, ":"); colon != -1 {
			ip = ip[:colon]
		}

		limiter := r.limiter.GetLimiter(ip)
		if !limiter.Allow() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"Rate limit exceeded"}`))
			return
		}
		next.ServeHTTP(w, req)
	})
}

// Middleware 3: Security Headers Enforcer
func (r *Router) SecurityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none';")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		w.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, req)
	})
}

// Middleware 4: Request ID Injection & Latency Logging
func (r *Router) LoggingAndRequestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		corrID := req.Header.Get("X-Request-ID")
		if corrID == "" {
			// Generate a cryptographically random UUIDv4 for the request ID (MED-04).
			var b [16]byte
			_, _ = rand.Read(b[:])
			b[6] = (b[6] & 0x0f) | 0x40 // version 4
			b[8] = (b[8] & 0x3f) | 0x80 // variant RFC4122
			corrID = fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
		}

		// Inject Request ID into Context and Header response
		ctx := context.WithValue(req.Context(), logger.CorrelationIDKey, corrID)
		w.Header().Set("X-Request-ID", corrID)

		isWebSocket := strings.ToLower(req.Header.Get("Upgrade")) == "websocket" || req.URL.Path == "/ws"
		start := time.Now()
		
		if isWebSocket {
			next.ServeHTTP(w, req.WithContext(ctx))
			slog.Info("WebSocket HTTP Request",
				"request_id", corrID,
				"method", req.Method,
				"path", req.URL.Path,
				"ip", req.RemoteAddr,
			)
			return
		}

		recorder := &ResponseRecorder{ResponseWriter: w, Status: http.StatusOK}
		next.ServeHTTP(recorder, req.WithContext(ctx))
		duration := time.Since(start)

		slog.Info("HTTP Request",
			"request_id", corrID,
			"method", req.Method,
			"path", req.URL.Path,
			"ip", req.RemoteAddr,
			"status", recorder.Status,
			"duration_ms", duration.Milliseconds(),
		)
	})
}

// Middleware 5: Authentication Validation
func (r *Router) AuthValidationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// Exempt login, onboard, registration, OPTIONS preflight, health endpoints from authentication
		path := req.URL.Path
		if req.Method == http.MethodOptions || path == "/healthz" || path == "/health" || strings.HasPrefix(path, "/api/v1/auth/") || path == "/ws" || strings.ToLower(req.Header.Get("Upgrade")) == "websocket" {
			next.ServeHTTP(w, req)
			return
		}

		authHeader := req.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"Unauthorized: missing bearer token"}`))
			return
		}

		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
		claims, err := r.verifyJWT(tokenStr)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(fmt.Sprintf(`{"error":"Unauthorized: %v"}`, err)))
			return
		}

		// Inject authenticated claims into request headers for downstream microservices
		if sub, ok := claims["sub"].(string); ok {
			req.Header.Set("X-User-Id", sub)
		}
		if role, ok := claims["role"].(string); ok {
			req.Header.Set("X-User-Role", role)
		}

		next.ServeHTTP(w, req)
	})
}

// verifyJWT validates a JWT string using algorithm-first verification (HIGH-03).
//
// Algorithm confusion fix: the token header's "alg" claim is read first and
// ONLY the matching key type is used — HMAC keys are never tried against RS256
// tokens and vice versa. No silent fallback between algorithms.
func (r *Router) verifyJWT(tokenStr string) (map[string]interface{}, error) {
	// Determine allowed algorithms from the token header before parsing.
	// golang-jwt enforces alg matching internally via WithValidMethods.

	// Phase 1: Decode header to determine algorithm (no signature check yet).
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 3 {
		return nil, errors.New("invalid token format")
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("invalid header encoding: %w", err)
	}
	var hdr struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(headerJSON, &hdr); err != nil {
		return nil, fmt.Errorf("invalid header JSON: %w", err)
	}

	// Phase 2: Select EXACTLY the key type that matches the declared algorithm.
	// No cross-algorithm fallback is permitted (prevents algorithm confusion attack).
	var keyFn jwt.Keyfunc
	switch hdr.Alg {
	case "HS256":
		// Internal service tokens use the shared HMAC secret.
		keyFn = func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return r.secretKey, nil
		}
	case "RS256":
		// External / OIDC tokens use JWKS public keys.
		keyFn = func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			kid, _ := t.Header["kid"].(string)
			return r.getPublicKey(kid)
		}
	default:
		return nil, fmt.Errorf("unsupported algorithm: %s", hdr.Alg)
	}

	// Phase 3: Parse and cryptographically verify the token.
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{hdr.Alg}),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
	)
	token, err := parser.Parse(tokenStr, keyFn)
	if err != nil {
		return nil, fmt.Errorf("jwt verification: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	// Verify issuer for RS256 (external OIDC tokens).
	if hdr.Alg == "RS256" && r.issuer != "" {
		iss, _ := claims["iss"].(string)
		if iss != r.issuer {
			return nil, fmt.Errorf("issuer mismatch: expected %s, got %s", r.issuer, iss)
		}
	}

	return map[string]interface{}(claims), nil
}

// getPublicKey retrieves an RSA public key by KID from the JWKS cache.
// If the key is absent, a fresh JWKS fetch is attempted before returning an error.
func (r *Router) getPublicKey(kid string) (*rsa.PublicKey, error) {
	if v, ok := r.jwksCache.Get(kid); ok {
		return v.(*rsa.PublicKey), nil
	}

	// Key not in cache — trigger a refresh.
	if err := r.fetchJWKS(); err != nil {
		return nil, err
	}

	if v, ok := r.jwksCache.Get(kid); ok {
		return v.(*rsa.PublicKey), nil
	}
	return nil, fmt.Errorf("key id %q not found in JWKS", kid)
}

// fetchJWKS fetches the remote JWKS endpoint and REPLACES the entire key cache.
// Replacing (not merging) ensures revoked/rotated keys are evicted (CRIT-14).
// A 5-minute minimum re-fetch window is enforced to avoid hammering the JWKS endpoint.
func (r *Router) fetchJWKS() error {
	r.cacheMutex.Lock()
	defer r.cacheMutex.Unlock()

	if time.Since(r.lastFetched) < 5*time.Minute {
		return nil
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(r.jwksURL)
	if err != nil {
		return fmt.Errorf("JWKS fetch: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("JWKS endpoint returned HTTP %d", resp.StatusCode)
	}

	type JWK struct {
		Kty string `json:"kty"`
		Kid string `json:"kid"`
		Use string `json:"use"`
		Alg string `json:"alg"`
		N   string `json:"n"`
		E   string `json:"e"`
	}
	var jwks struct {
		Keys []JWK `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return fmt.Errorf("JWKS JSON decode: %w", err)
	}

	// Flush the old cache and populate from the fresh response (CRIT-14).
	r.jwksCache.Flush()
	for _, key := range jwks.Keys {
		if key.Kty == "RSA" && key.Use == "sig" {
			pubKey, err := decodeRSAKeyBytes(key.N, key.E)
			if err == nil {
				r.jwksCache.SetDefault(key.Kid, pubKey)
			}
		}
	}

	r.lastFetched = time.Now()
	slog.Info("JWKS refreshed", "key_count", len(jwks.Keys))
	return nil
}

func decodeRSAKeyBytes(nStr, eStr string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nStr)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eStr)
	if err != nil {
		return nil, err
	}

	n := new(big.Int).SetBytes(nBytes)
	var e int
	for _, b := range eBytes {
		e = (e << 8) + int(b)
	}

	return &rsa.PublicKey{
		N: n,
		E: e,
	}, nil
}

// gzipBufferedWriter captures response bytes before compression
// so that the correct Content-Length can be set after compressing.
type gzipBufferedWriter struct {
	http.ResponseWriter
	buf        bytes.Buffer
	statusCode int
	header     http.Header
	wroteHeader bool
}

func newGzipBufferedWriter(w http.ResponseWriter) *gzipBufferedWriter {
	return &gzipBufferedWriter{
		ResponseWriter: w,
		statusCode:     http.StatusOK,
		header:         w.Header(),
	}
}

func (g *gzipBufferedWriter) WriteHeader(code int) {
	if !g.wroteHeader {
		g.statusCode = code
		g.wroteHeader = true
	}
}

func (g *gzipBufferedWriter) Write(b []byte) (int, error) {
	return g.buf.Write(b)
}

// GzipCompressionMiddleware compresses responses for clients that accept gzip.
// It buffers the entire handler output, compresses it, then sets the correct
// Content-Length before sending — preventing the "Content-Length mismatch" bug
// that caused dart:io to report "HttpConnection closed while receiving data".
//
// Compression is SKIPPED when:
//   - Client does not send Accept-Encoding: gzip
//   - Request is a WebSocket upgrade
//   - Request contains Expect: 100-continue (dart:io sends this for POST requests;
//     the combination of an interim 100 Continue + gzip buffering produces a
//     malformed response sequence that dart:io cannot parse)
func (r *Router) GzipCompressionMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// Skip compression for WebSocket upgrades, non-gzip clients,
		// or Expect: 100-continue requests (dart:io POST bodies).
		if strings.ToLower(req.Header.Get("Upgrade")) == "websocket" ||
			!strings.Contains(req.Header.Get("Accept-Encoding"), "gzip") ||
			strings.EqualFold(req.Header.Get("Expect"), "100-continue") {
			next.ServeHTTP(w, req)
			return
		}

		// Capture the handler output into an in-memory buffer.
		buf := newGzipBufferedWriter(w)
		next.ServeHTTP(buf, req)

		// Compress the buffered body.
		var compressed bytes.Buffer
		gz := gzip.NewWriter(&compressed)
		_, _ = gz.Write(buf.buf.Bytes())
		_ = gz.Close() // flushes and writes gzip trailer

		// Write correct headers BEFORE WriteHeader so they aren't lost.
		w.Header().Del("Content-Length") // remove any stale raw-size header
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Set("Content-Length", strconv.Itoa(compressed.Len()))

		w.WriteHeader(buf.statusCode)
		_, _ = w.Write(compressed.Bytes())
	})
}


// Ensure unused imports are referenced to prevent compile errors.
var (
	_ = sha256.New
	_ = crypto.SHA256
	_ = rsa.VerifyPKCS1v15
	_ = new(big.Int)
)

type webSocketTransport struct {
	Transport http.RoundTripper
}

func (t *webSocketTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Restore WebSocket upgrade headers stripped by ReverseProxy
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Upgrade", "websocket")
	
	transport := t.Transport
	if transport == nil {
		transport = http.DefaultTransport
	}
	return transport.RoundTrip(req)
}
