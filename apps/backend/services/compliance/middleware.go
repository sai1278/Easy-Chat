// Package compliance provides middleware for GDPR-compliant request processing:
// PII masking in logs, consent gate enforcement, and audit event injection.
package compliance

import (
	"context"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
)

// ─────────────────────────────────────────────────────────────────────────────
// PII Masking Middleware
// Strips or replaces PII from log-forwarded headers before they hit Loki/stdout.
// ─────────────────────────────────────────────────────────────────────────────

// PII patterns for log sanitisation
var piiPatterns = []*regexp.Regexp{
	regexp.MustCompile(`[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}`), // email
	regexp.MustCompile(`\b\d{10,15}\b`),                                       // phone numbers
	regexp.MustCompile(`(?i)(password|token|secret|key)=\S+`),                 // credentials in query strings
	regexp.MustCompile(`\b(?:\d{4}[- ]?){3}\d{4}\b`),                         // credit card
}

// MaskPII replaces PII patterns in a string with redacted placeholders.
func MaskPII(s string) string {
	for _, re := range piiPatterns {
		s = re.ReplaceAllString(s, "[REDACTED]")
	}
	return s
}

// AuditMiddleware injects compliance audit events for every API request.
// It emits an audit record to the database after each request completes.
func AuditMiddleware(svc *Service, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Wrap response writer to capture status code
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(rw, r)

		userID := r.Header.Get("X-User-ID")
		requestID := r.Header.Get("X-Request-ID")
		ipHash := hashValue(r.Header.Get("X-Forwarded-For"))
		outcome := "success"
		if rw.statusCode >= 400 {
			outcome = "failure"
		}

		// Mask PII from path before storing in audit log
		path := MaskPII(r.URL.Path)

		_ = svc.EmitAuditEvent(r.Context(), AuditEvent{
			ActorID:      userID,
			ActorType:    "user",
			EventType:    "api.request",
			ResourceType: "endpoint",
			ResourceID:   path,
			Action:       strings.ToLower(r.Method),
			Outcome:      outcome,
			RequestID:    requestID,
			Metadata: map[string]any{
				"method":      r.Method,
				"path":        path,
				"status_code": rw.statusCode,
				"ip_hash":     ipHash,
			},
		})
	})
}

// ConsentGate is a middleware factory that blocks request processing if the
// authenticated user has not granted the required consent purpose.
func ConsentGate(svc *Service, purpose ConsentPurpose) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := r.Header.Get("X-User-ID")
			if userID == "" {
				next.ServeHTTP(w, r)
				return
			}

			granted, err := svc.HasActiveConsent(r.Context(), userID, purpose)
			if err != nil {
				slog.Error("ConsentGate check failed", "purpose", purpose, "error", err)
				writeError(w, http.StatusServiceUnavailable, "consent check unavailable")
				return
			}
			if !granted {
				writeError(w, http.StatusForbidden,
					"Processing requires consent for purpose '"+string(purpose)+"'. Please update your privacy settings.")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// RegionRoutingMiddleware enforces that requests for user data are routed to
// the correct regional cluster based on the user's data residency assignment.
// This satisfies GDPR Art.44-49 data transfer restrictions.
func RegionRoutingMiddleware(svc *Service, currentRegion DataRegion, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			next.ServeHTTP(w, r)
			return
		}

		userRegion, err := svc.GetUserRegion(r.Context(), userID)
		if err != nil {
			// Log and allow — do not block on residency lookup failures
			slog.Error("Region routing lookup failed", "user_id", userID, "error", err)
			next.ServeHTTP(w, r)
			return
		}

		// If request lands in the wrong region, redirect (or return 307 for client to follow)
		if userRegion != currentRegion {
			target := regionEndpoint(userRegion)
			if target != "" {
				slog.Info("Cross-region redirect", "user_id", userID, "from", currentRegion, "to", userRegion)
				http.Redirect(w, r, target+r.RequestURI, http.StatusTemporaryRedirect)
				return
			}
		}

		// Inject region into context for downstream handlers
		ctx := context.WithValue(r.Context(), contextKeyRegion{}, userRegion)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// DataResidencyHeader sets the X-Data-Residency header on all responses.
// Allows the mobile client to verify data is processed in the expected region.
func DataResidencyHeader(region DataRegion, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Data-Residency", string(region))
		w.Header().Set("X-Data-Sovereignty", DataSovereignty[region])
		next.ServeHTTP(w, r)
	})
}

type contextKeyRegion struct{}

func regionEndpoint(region DataRegion) string {
	endpoints := map[DataRegion]string{
		RegionEUWest1:      "https://eu.api.easychat.app",
		RegionUSEast1:      "https://us.api.easychat.app",
		RegionUSWest1:      "https://us-west.api.easychat.app",
		RegionAPSoutheast1: "https://ap.api.easychat.app",
	}
	return endpoints[region]
}

// responseWriter wraps http.ResponseWriter to capture the HTTP status code.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
