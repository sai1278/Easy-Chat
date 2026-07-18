package idempotency

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var (
	ErrRequestInProgress = errors.New("request already in progress")
)

// Store defines cache interaction requirements for idempotency locks and logs.
type Store interface {
	Get(ctx context.Context, key string) (string, error)
	Set(ctx context.Context, key string, value string, ttl time.Duration) error
	SetNX(ctx context.Context, key string, value string, ttl time.Duration) (bool, error)
	Del(ctx context.Context, key string) error
}

// CachedResponse captures response state to replay to duplicate requests.
type CachedResponse struct {
	Status int               `json:"status"`
	Body   []byte            `json:"body"`
	Header map[string]string `json:"header"`
}

// Engine coordinates request checking and caching.
type Engine struct {
	store Store
	ttl   time.Duration
}

func NewEngine(store Store, ttl time.Duration) *Engine {
	return &Engine{
		store: store,
		ttl:   ttl,
	}
}

// Acquire attempts to claim the execution path for a request fingerprint.
// Returns (CachedResponse, true, nil) if a completed response is cached.
// Returns (nil, false, ErrRequestInProgress) if a duplicate request is currently executing.
// Returns (nil, false, nil) if the lock is claimed and execution should proceed.
func (e *Engine) Acquire(ctx context.Context, key string) (*CachedResponse, bool, error) {
	lockKey := "nearby:idempotency:lock:" + key
	cacheKey := "nearby:idempotency:cache:" + key

	// 1. Check if a completed response is already cached
	val, err := e.store.Get(ctx, cacheKey)
	if err == nil && val != "" {
		var cache CachedResponse
		if err := json.Unmarshal([]byte(val), &cache); err == nil {
			return &cache, true, nil
		}
	}

	// 2. Attempt to acquire an execution lock (lock timeout 15 seconds)
	acquired, err := e.store.SetNX(ctx, lockKey, "IN_PROGRESS", 15*time.Second)
	if err != nil {
		return nil, false, err
	}

	if !acquired {
		return nil, false, ErrRequestInProgress
	}

	return nil, false, nil
}

// Commit saves the generated response payload and releases the execution lock.
func (e *Engine) Commit(ctx context.Context, key string, status int, body []byte, headers map[string]string) error {
	lockKey := "nearby:idempotency:lock:" + key
	cacheKey := "nearby:idempotency:cache:" + key

	cache := CachedResponse{
		Status: status,
		Body:   body,
		Header: headers,
	}

	payload, err := json.Marshal(cache)
	if err != nil {
		return err
	}

	// Save payload
	if err := e.store.Set(ctx, cacheKey, string(payload), e.ttl); err != nil {
		return err
	}

	// Remove lock
	return e.store.Del(ctx, lockKey)
}

// Release aborts the lock if execution failed (releasing write lock for retry).
func (e *Engine) Release(ctx context.Context, key string) error {
	lockKey := "nearby:idempotency:lock:" + key
	return e.store.Del(ctx, lockKey)
}
