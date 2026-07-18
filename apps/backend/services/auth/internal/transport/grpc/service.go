// Package grpc provides the internal gRPC server for the auth service.
// ValidateSession performs a real JWT signature verification rather than
// returning a hardcoded (true, nil) (fixes CRIT-05).
package grpc

import (
	"context"
	"errors"
	"fmt"

	"github.com/golang-jwt/jwt/v5"
)

// AuthServiceServer validates session tokens for internal microservice calls.
type AuthServiceServer struct {
	parser *jwt.Parser
	keyFn  jwt.Keyfunc
	issuer string
}

// NewAuthServiceServer constructs the gRPC auth server.
//
// signingKey must match the key used by AuthUsecase.generateJWT.
// For []byte (HS256) keys, pass the raw secret slice.
func NewAuthServiceServer(signingKey interface{}, issuer string) (*AuthServiceServer, error) {
	var keyFn jwt.Keyfunc
	switch k := signingKey.(type) {
	case []byte:
		keyFn = func(*jwt.Token) (interface{}, error) { return k, nil }
	default:
		return nil, errors.New("unsupported signing key type; provide []byte for HS256")
	}
	return &AuthServiceServer{
		parser: jwt.NewParser(
			jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
			jwt.WithIssuedAt(),
			jwt.WithExpirationRequired(),
		),
		keyFn:  keyFn,
		issuer: issuer,
	}, nil
}

// ValidateSession parses and cryptographically verifies the JWT.
// Returns (true, nil) only for tokens with a valid signature and unexpired claims.
// Returns (false, err) for any invalid token (CRIT-05: no longer always returns true).
func (s *AuthServiceServer) ValidateSession(ctx context.Context, tokenStr string) (bool, error) {
	if tokenStr == "" {
		return false, errors.New("empty token")
	}

	token, err := s.parser.Parse(tokenStr, s.keyFn)
	if err != nil {
		return false, fmt.Errorf("jwt parse: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return false, errors.New("invalid token claims")
	}

	// Verify issuer if configured.
	if s.issuer != "" {
		iss, _ := claims["iss"].(string)
		if iss != s.issuer {
			return false, fmt.Errorf("issuer mismatch: expected %s got %s", s.issuer, iss)
		}
	}

	return true, nil
}
