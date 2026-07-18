package errors

import (
	"encoding/json"
	"net/http"
)

// InvalidParam details specific field violations for validation failures.
type InvalidParam struct {
	Name   string `json:"name"`
	Reason string `json:"reason"`
}

// ProblemDetails matches RFC 7807 specification for HTTP API error payloads.
type ProblemDetails struct {
	Type          string         `json:"type"`
	Title         string         `json:"title"`
	Status        int            `json:"status"`
	Detail        string         `json:"detail"`
	Instance      string         `json:"instance,omitempty"`
	Code          string         `json:"code"`
	InvalidParams []InvalidParam `json:"invalid_params,omitempty"`
}

func (p *ProblemDetails) Error() string {
	return p.Detail
}

// NewProblemDetails creates a configured error definition wrapper.
func NewProblemDetails(status int, errType, title, detail, code string) *ProblemDetails {
	return &ProblemDetails{
		Type:     "https://api.nearbyconnect.com/errors/" + errType,
		Title:    title,
		Status:   status,
		Detail:   detail,
		Code:     code,
	}
}

// WriteJSON serializes the error payload into the HTTP response.
func (p *ProblemDetails) WriteJSON(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(p.Status)
	_ = json.NewEncoder(w).Encode(p)
}

// Standard system error class definitions
var (
	ErrUnauthorized = &ProblemDetails{
		Type:   "https://api.nearbyconnect.com/errors/unauthorized",
		Title:  "Unauthorized Access",
		Status: http.StatusUnauthorized,
		Detail: "Bearer token is invalid, missing, or has expired.",
		Code:   "UNAUTHORIZED",
	}

	ErrForbidden = &ProblemDetails{
		Type:   "https://api.nearbyconnect.com/errors/forbidden",
		Title:  "Forbidden Resource",
		Status: http.StatusForbidden,
		Detail: "You do not have access rights to this data resource.",
		Code:   "FORBIDDEN",
	}

	ErrNotFound = &ProblemDetails{
		Type:   "https://api.nearbyconnect.com/errors/not-found",
		Title:  "Resource Not Found",
		Status: http.StatusNotFound,
		Detail: "The requested object or routing path could not be located.",
		Code:   "NOT_FOUND",
	}

	ErrRateLimitExceeded = &ProblemDetails{
		Type:   "https://api.nearbyconnect.com/errors/rate-limit-exceeded",
		Title:  "Rate Limit Exceeded",
		Status: http.StatusTooManyRequests,
		Detail: "Maximum request limits exceeded. Please wait before retrying.",
		Code:   "RATE_LIMIT_EXCEEDED",
	}

	ErrInternalServer = &ProblemDetails{
		Type:   "https://api.nearbyconnect.com/errors/internal-server",
		Title:  "Internal Server Failure",
		Status: http.StatusInternalServerError,
		Detail: "An unexpected system error occurred. Please contact administration.",
		Code:   "INTERNAL_SERVER_ERROR",
	}
)
