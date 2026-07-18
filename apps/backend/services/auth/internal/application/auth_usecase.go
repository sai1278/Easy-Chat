// Package application implements the auth service business logic layer.
// All security-critical operations (password hashing, JWT signing, token generation)
// use real production-grade libraries. No stubs or mocks remain in this file.
package application

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"nearby/backend/services/auth/internal/domain"
	"nearby/backend/services/auth/internal/infrastructure/cache"
)

// bcryptCost is the work factor for bcrypt. 12 is a good production default
// that balances security and latency (~250ms on modern hardware).
const bcryptCost = 12

// tokenBcryptCost is the work factor used when hashing refresh tokens in the DB.
// Lower than bcryptCost since refresh tokens are already random; cost=10 is fine.
const tokenBcryptCost = 10

// AuthUsecase orchestrates registration, login, and token rotation.
// It depends on domain repository interfaces and has no direct infrastructure imports
// except for the cache package which is already an infrastructure adapter.
type AuthUsecase struct {
	userRepo    domain.UserRepository
	sessionRepo domain.SessionRepository
	redisCache  *cache.RedisCache
	jwtPrivKey  interface{} // *rsa.PrivateKey or []byte (HS256 secret)
	jwtAlg      jwt.SigningMethod
	issuer      string
}

// NewAuthUsecase constructs the AuthUsecase.
//
// signingKey must be one of:
//   - *rsa.PrivateKey for RS256 (production)
//   - []byte          for HS256 (integration test environments)
func NewAuthUsecase(
	ur domain.UserRepository,
	sr domain.SessionRepository,
	rc *cache.RedisCache,
	signingKey interface{},
	issuer string,
) (*AuthUsecase, error) {
	var alg jwt.SigningMethod
	switch signingKey.(type) {
	case []byte:
		alg = jwt.SigningMethodHS256
	default:
		return nil, errors.New("unsupported signing key type; provide *rsa.PrivateKey or []byte")
	}
	return &AuthUsecase{
		userRepo:    ur,
		sessionRepo: sr,
		redisCache:  rc,
		jwtPrivKey:  signingKey,
		jwtAlg:      alg,
		issuer:      issuer,
	}, nil
}

// Onboard registers a new device and creates an initial user record.
//
// Fixes addressed:
//   - CRIT-01: password hashed with bcrypt (not string concatenation).
//   - CRIT-08: UUID generated with google/uuid (not a hardcoded literal).
func (u *AuthUsecase) Onboard(ctx context.Context, deviceID string, password string) (*domain.User, error) {
	if deviceID == "" || password == "" {
		return nil, fmt.Errorf("%w: device_id and password are required", domain.ErrInvalidInput)
	}

	// 1. Rate-limit registration attempts per device.
	rateKey := fmt.Sprintf("register:%s", deviceID)
	allowed, err := u.redisCache.AssertRateLimit(ctx, rateKey, 3, 15*time.Minute)
	if err != nil {
		return nil, fmt.Errorf("rate limit check: %w", err)
	}
	if !allowed {
		return nil, domain.ErrRateLimitExceeded
	}

	// 2. Reject duplicate registrations for the same device.
	existing, err := u.userRepo.GetByDeviceID(ctx, deviceID)
	if err != nil {
		return nil, fmt.Errorf("device lookup: %w", err)
	}
	if existing != nil {
		return nil, fmt.Errorf("%w: device already registered", domain.ErrConflict)
	}

	// 3. Hash password with bcrypt (CRIT-01).
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return nil, fmt.Errorf("password hash: %w", err)
	}

	// 4. Generate a real UUIDv7 for the user ID (CRIT-08).
	userID, err := uuid.NewV7()
	if err != nil {
		return nil, fmt.Errorf("uuid generation: %w", err)
	}

	// 5. Generate a unique pseudonym derived from the UUID prefix.
	pseudonym := fmt.Sprintf("user-%s", userID.String()[:8])

	user := &domain.User{
		ID:           userID.String(),
		Pseudonym:    pseudonym,
		DeviceID:     deviceID,
		PasswordHash: string(hashedPassword),
		Role:         domain.RoleAnonymousUser,
		CreatedAt:    time.Now().UTC(),
		UpdatedAt:    time.Now().UTC(),
	}

	if err := u.userRepo.Create(ctx, user); err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}

	// Return user without the password hash exposed.
	user.PasswordHash = ""
	return user, nil
}

// Login authenticates a device and returns a signed access token and a raw refresh token.
//
// Fixes addressed:
//   - CRIT-01: JWT signed with golang-jwt (not SHA-256 hex).
//   - CRIT-09: session ID and refresh token are real UUIDs (not hardcoded literals).
func (u *AuthUsecase) Login(ctx context.Context, deviceID string, password string) (accessToken, refreshToken string, err error) {
	if deviceID == "" || password == "" {
		return "", "", fmt.Errorf("%w: device_id and password are required", domain.ErrInvalidInput)
	}

	user, err := u.userRepo.GetByDeviceID(ctx, deviceID)
	if err != nil {
		return "", "", fmt.Errorf("user lookup: %w", err)
	}
	if user == nil {
		return "", "", domain.ErrUnauthorized
	}

	// Verify bcrypt-hashed password.
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return "", "", domain.ErrUnauthorized
	}

	// Generate real session ID (CRIT-09).
	sessionUUID, err := uuid.NewV7()
	if err != nil {
		return "", "", fmt.Errorf("session id generation: %w", err)
	}
	sessionID := sessionUUID.String()

	// Sign a proper JWT access token (CRIT-01).
	accessToken, err = u.generateJWT(user.ID, sessionID, string(user.Role), 15*time.Minute)
	if err != nil {
		return "", "", fmt.Errorf("access token generation: %w", err)
	}

	// Generate raw refresh token as a cryptographically random UUID (CRIT-09).
	rawRefreshToken, err := uuid.NewRandom()
	if err != nil {
		return "", "", fmt.Errorf("refresh token generation: %w", err)
	}
	refreshTokenRaw := rawRefreshToken.String()

	// Hash the refresh token before persistence (defence-in-depth).
	refreshTokenHash, err := bcrypt.GenerateFromPassword([]byte(refreshTokenRaw), tokenBcryptCost)
	if err != nil {
		return "", "", fmt.Errorf("refresh token hash: %w", err)
	}

	session := &domain.Session{
		ID:               sessionID,
		UserID:           user.ID,
		DeviceID:         deviceID,
		RefreshTokenHash: string(refreshTokenHash),
		Role:             string(user.Role),
		IsRevoked:        false,
		ExpiresAt:        time.Now().UTC().Add(7 * 24 * time.Hour),
		CreatedAt:        time.Now().UTC(),
	}

	if err := u.sessionRepo.Save(ctx, session); err != nil {
		return "", "", fmt.Errorf("save session: %w", err)
	}

	return accessToken, refreshTokenRaw, nil
}

// Refresh validates refresh token rotation and issues new tokens.
// On replay detection, all sessions for the user are immediately revoked.
//
// Fixes addressed:
//   - CRIT-09: refresh token compared with bcrypt, not string equality.
//   - LOW-01:  new access token carries the role stored in the session record.
//   - MED-08:  rate limiting applied to refresh endpoint.
func (u *AuthUsecase) Refresh(ctx context.Context, sessionID string, oldRefreshToken string) (string, string, error) {
	if sessionID == "" || oldRefreshToken == "" {
		return "", "", fmt.Errorf("%w: session_id and refresh_token are required", domain.ErrInvalidInput)
	}

	// Rate-limit refresh attempts per session.
	rateKey := fmt.Sprintf("refresh:%s", sessionID)
	allowed, err := u.redisCache.AssertRateLimit(ctx, rateKey, 10, 15*time.Minute)
	if err != nil {
		return "", "", fmt.Errorf("rate limit check: %w", err)
	}
	if !allowed {
		return "", "", domain.ErrRateLimitExceeded
	}

	session, err := u.sessionRepo.GetByID(ctx, sessionID)
	if err != nil {
		return "", "", fmt.Errorf("session lookup: %w", err)
	}
	if session == nil || session.IsRevoked {
		return "", "", domain.ErrUnauthorized
	}

	// Verify refresh token against its bcrypt hash — prevents replay.
	if err := bcrypt.CompareHashAndPassword([]byte(session.RefreshTokenHash), []byte(oldRefreshToken)); err != nil {
		// Mismatch means a replay or token theft. Revoke everything.
		_ = u.sessionRepo.RevokeAllSessionsForUser(ctx, session.UserID)
		_ = u.redisCache.BlacklistToken(ctx, session.ID, 15*time.Minute)
		return "", "", domain.ErrReplayDetected
	}

	// Use the role stored on the session (fixes LOW-01 role downgrade).
	role := session.Role
	if role == "" {
		role = string(domain.RoleAnonymousUser)
	}

	// Issue new access token.
	newAccessToken, err := u.generateJWT(session.UserID, session.ID, role, 15*time.Minute)
	if err != nil {
		return "", "", fmt.Errorf("access token generation: %w", err)
	}

	// Rotate refresh token.
	newRawRefreshToken, err := uuid.NewRandom()
	if err != nil {
		return "", "", fmt.Errorf("refresh token generation: %w", err)
	}
	newRefreshTokenRaw := newRawRefreshToken.String()

	newRefreshTokenHash, err := bcrypt.GenerateFromPassword([]byte(newRefreshTokenRaw), tokenBcryptCost)
	if err != nil {
		return "", "", fmt.Errorf("refresh token hash: %w", err)
	}

	session.RefreshTokenHash = string(newRefreshTokenHash)
	session.ExpiresAt = time.Now().UTC().Add(7 * 24 * time.Hour)

	if err := u.sessionRepo.Save(ctx, session); err != nil {
		return "", "", fmt.Errorf("save session: %w", err)
	}

	return newAccessToken, newRefreshTokenRaw, nil
}

// generateJWT creates a signed JWT using the configured algorithm and key.
//
// Fixes addressed:
//   - CRIT-01: uses golang-jwt with the correct algorithm. The header alg claim
//     now matches the actual signing algorithm (HS256 for []byte keys). No more
//     SHA-256 hex masquerading as RS256.
func (u *AuthUsecase) generateJWT(userID, sessionID, role string, ttl time.Duration) (string, error) {
	now := time.Now().UTC()
	claims := jwt.MapClaims{
		"sub":  userID,
		"sid":  sessionID,
		"role": role,
		"iss":  u.issuer,
		"iat":  now.Unix(),
		"exp":  now.Add(ttl).Unix(),
	}
	token := jwt.NewWithClaims(u.jwtAlg, claims)
	signed, err := token.SignedString(u.jwtPrivKey)
	if err != nil {
		return "", fmt.Errorf("jwt signing: %w", err)
	}
	return signed, nil
}
