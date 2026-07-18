package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log"
	"net/http"
	"time"

	"nearby/backend/internal/pkg/errors"
	"nearby/backend/internal/pkg/idempotency"
)

type contextKey string

const (
	CorrelationIDKey contextKey = "CorrelationID"
)

// ResponseRecorder captures the status and payload to log and cache.
type ResponseRecorder struct {
	http.ResponseWriter
	Status int
	Body   []byte
}

func (r *ResponseRecorder) WriteHeader(status int) {
	r.Status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *ResponseRecorder) Write(b []byte) (int, error) {
	if r.Status == 0 {
		r.Status = http.StatusOK
	}
	r.Body = append(r.Body, b...)
	return r.ResponseWriter.Write(b)
}

// CorrelationIDMiddleware injects a unique tracking code.
func CorrelationIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		corrID := r.Header.Get("X-Correlation-ID")
		if corrID == "" {
			bytes := make([]byte, 16)
			_, _ = rand.Read(bytes)
			corrID = hex.EncodeToString(bytes)
		}
		w.Header().Set("X-Correlation-ID", corrID)
		ctx := context.WithValue(r.Context(), CorrelationIDKey, corrID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequestLogger outputs request stats.
func RequestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		corrID, _ := r.Context().Value(CorrelationIDKey).(string)

		recorder := &ResponseRecorder{ResponseWriter: w}
		next.ServeHTTP(recorder, r)

		log.Printf("[%s] %s %s | Status: %d | Latency: %v",
			corrID, r.Method, r.URL.Path, recorder.Status, time.Since(start))
	})
}

// RecoveryMiddleware catches panics.
func RecoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				corrID, _ := r.Context().Value(CorrelationIDKey).(string)
				log.Printf("[%s] CRITICAL: Handler Panic: %v", corrID, err)
				
				problem := errors.ErrInternalServer
				problem.Instance = r.URL.Path
				problem.WriteJSON(w)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// IdempotencyMiddleware rejects duplicate requests at the API Gateway level.
func IdempotencyMiddleware(engine *idempotency.Engine) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Only check state-modifying requests that require idempotency
			if r.Method != http.MethodPost && r.Method != http.MethodPatch && r.Method != http.MethodPut {
				next.ServeHTTP(w, r)
				return
			}

			key := r.Header.Get("Idempotency-Key")
			if key == "" {
				// Bypass if header not supplied (or enforce it depending on policy)
				next.ServeHTTP(w, r)
				return
			}

			ctx := r.Context()
			cached, exists, err := engine.Acquire(ctx, key)
			if err != nil {
				if err == idempotency.ErrRequestInProgress {
					problem := errors.NewProblemDetails(
						http.StatusConflict,
						"idempotency-conflict",
						"Request In Progress",
						"A duplicate request is currently being processed. Please wait.",
						"IDEMPOTENCY_CONFLICT",
					)
					problem.Instance = r.URL.Path
					problem.WriteJSON(w)
					return
				}
				log.Printf("Idempotency Acquire Error: %v", err)
				next.ServeHTTP(w, r)
				return
			}

			if exists && cached != nil {
				// Replay the cached response
				for k, v := range cached.Header {
					w.Header().Set(k, v)
				}
				w.Header().Set("X-Cache-Replayed", "true")
				w.WriteHeader(cached.Status)
				_, _ = w.Write(cached.Body)
				return
			}

			// Run execution and capture results
			recorder := &ResponseRecorder{ResponseWriter: w}
			
			// Setup defer rollback/commit trigger
			defer func() {
				// If handler panicked, release the lock so clients can retry
				if rec := recover(); rec != nil {
					_ = engine.Release(ctx, key)
					panic(rec) // re-panic after releasing to let recovery middleware handle it
				}

				// Release lock on server errors (5xx)
				if recorder.Status >= 500 {
					_ = engine.Release(ctx, key)
					return
				}

				// Cache headers we want to keep
				headersToCache := map[string]string{
					"Content-Type": w.Header().Get("Content-Type"),
				}

				// Save response to Redis
				_ = engine.Commit(ctx, key, recorder.Status, recorder.Body, headersToCache)
			}()

			next.ServeHTTP(recorder, r)
		})
	}
}
