package middleware

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

type contextKey string

const (
	UserContextKey contextKey = "user_claims"
)

// JWTClaims represents the standard and custom claims validated from the JWT.
type JWTClaims struct {
	Subject   string   `json:"sub"`
	Issuer    string   `json:"iss"`
	Audience  string   `json:"aud"`
	ExpiresAt int64    `json:"exp"`
	Roles     []string `json:"roles"`
	Scopes    []string `json:"scopes"`
}

// JWK represents a JSON Web Key definition.
type JWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type JWKS struct {
	Keys []JWK `json:"keys"`
}

// OIDCMiddleware manages JWKS caching and token validation checks.
type OIDCMiddleware struct {
	jwksURL      string
	issuer       string
	audience     string
	jwksCache    map[string]*rsa.PublicKey
	cacheMutex   sync.RWMutex
	lastFetched  time.Time
	cacheTimeout time.Duration
}

func NewOIDCMiddleware(jwksURL, issuer, audience string) *OIDCMiddleware {
	return &OIDCMiddleware{
		jwksURL:      jwksURL,
		issuer:       issuer,
		audience:     audience,
		jwksCache:    make(map[string]*rsa.PublicKey),
		cacheTimeout: 1 * time.Hour,
	}
}

// ValidateJWT validates JWT signatures and claims.
func (m *OIDCMiddleware) ValidateJWT(tokenStr string) (*JWTClaims, error) {
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 3 {
		return nil, errors.New("malformed JWT structure")
	}

	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("invalid header base64: %w", err)
	}

	var header struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return nil, fmt.Errorf("invalid header JSON: %w", err)
	}

	if header.Alg != "RS256" {
		return nil, fmt.Errorf("unsupported algorithm: %s", header.Alg)
	}

	// Fetch public key
	pubKey, err := m.getPublicKey(header.Kid)
	if err != nil {
		return nil, fmt.Errorf("public key lookup failure: %w", err)
	}

	// Verify RSA signature
	payload := parts[0] + "." + parts[1]
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, fmt.Errorf("invalid signature base64: %w", err)
	}

	hasher := sha256.New()
	hasher.Write([]byte(payload))
	hashed := hasher.Sum(nil)

	if err := rsa.VerifyPKCS1v15(pubKey, crypto.SHA256, hashed, sig); err != nil {
		return nil, fmt.Errorf("cryptographic signature mismatch: %w", err)
	}

	// Parse and validate claims
	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("invalid payload base64: %w", err)
	}

	var claims JWTClaims
	if err := json.Unmarshal(payloadJSON, &claims); err != nil {
		return nil, fmt.Errorf("invalid payload JSON: %w", err)
	}

	if claims.ExpiresAt < time.Now().Unix() {
		return nil, errors.New("token expired")
	}

	if claims.Issuer != m.issuer {
		return nil, fmt.Errorf("issuer mismatch: expected %s, got %s", m.issuer, claims.Issuer)
	}

	if claims.Audience != m.audience {
		return nil, fmt.Errorf("audience mismatch: expected %s, got %s", m.audience, claims.Audience)
	}

	return &claims, nil
}

func (m *OIDCMiddleware) getPublicKey(kid string) (*rsa.PublicKey, error) {
	m.cacheMutex.RLock()
	key, ok := m.jwksCache[kid]
	m.cacheMutex.RUnlock()
	if ok {
		return key, nil
	}

	// Update cache
	if err := m.fetchJWKS(); err != nil {
		return nil, err
	}

	m.cacheMutex.RLock()
	key, ok = m.jwksCache[kid]
	m.cacheMutex.RUnlock()
	if !ok {
		return nil, fmt.Errorf("key id %s not found in JWKS", kid)
	}
	return key, nil
}

func (m *OIDCMiddleware) fetchJWKS() error {
	m.cacheMutex.Lock()
	defer m.cacheMutex.Unlock()

	// Rate limit fetch attempts
	if time.Since(m.lastFetched) < 5*time.Second {
		return nil
	}

	resp, err := http.Get(m.jwksURL)
	if err != nil {
		return fmt.Errorf("failed fetching JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected JWKS HTTP code: %d", resp.StatusCode)
	}

	var jwks JWKS
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return fmt.Errorf("invalid JWKS JSON: %w", err)
	}

	for _, key := range jwks.Keys {
		if key.Kty == "RSA" && key.Use == "sig" {
			pubKey, err := decodeRSAKey(key.N, key.E)
			if err == nil {
				m.jwksCache[key.Kid] = pubKey
			}
		}
	}

	m.lastFetched = time.Now()
	return nil
}

func decodeRSAKey(nStr, eStr string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nStr)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eStr)
	if err != nil {
		return nil, err
	}

	n := new(big.Int).SetBytes(nBytes)
	
	// Convert exponent bytes to int
	var e int
	for _, b := range eBytes {
		e = (e << 8) + int(b)
	}

	return &rsa.PublicKey{
		N: n,
		E: e,
	}, nil
}

// HandlerMiddleware wraps HTTP handler checks enforcing OIDC signatures and target roles.
func (m *OIDCMiddleware) HandlerMiddleware(requiredRole string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized: missing bearer token", http.StatusUnauthorized)
			return
		}

		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
		claims, err := m.ValidateJWT(tokenStr)
		if err != nil {
			http.Error(w, fmt.Sprintf("Unauthorized: invalid token: %v", err), http.StatusUnauthorized)
			return
		}

		// Enforce role claim checks
		if requiredRole != "" {
			hasRole := false
			for _, role := range claims.Roles {
				if role == requiredRole {
					hasRole = true
					break
				}
			}
			if !hasRole {
				http.Error(w, "Forbidden: insufficient permissions", http.StatusForbidden)
				return
			}
		}

		// Inject claims into context
		ctx := context.WithValue(r.Context(), UserContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
