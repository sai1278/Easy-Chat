package http

import (
	"context"
	"net"
	"net/http"
	"strconv"
	"time"
)

// RedisCommander defines the subset of redis commands required for Lua evaluation.
type RedisCommander interface {
	Eval(ctx context.Context, script string, keys []string, args ...interface{}) (interface{}, error)
}

// RateLimiter wraps Redis connection and config limit parameters.
type RateLimiter struct {
	redis        RedisCommander
	maxRequests  int
	windowSecs   int
}

func NewRateLimiter(redis RedisCommander, maxRequests, windowSecs int) *RateLimiter {
	return &RateLimiter{
		redis:       redis,
		maxRequests: maxRequests,
		windowSecs:  windowSecs,
	}
}

// slidingWindowScript is an atomic Lua script implementing sliding-window logic.
const slidingWindowScript = `
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])

local clearBefore = now - window
redis.call('ZREMRANGEBYSCORE', key, 0, clearBefore)

local currentRequests = redis.call('ZCARD', key)
if currentRequests < limit then
    redis.call('ZADD', key, now, now)
    redis.call('EXPIRE', key, window)
    return 1
else
    return 0
end
`

// LimitHandler wraps HTTP calls, checking rate limits before execution.
func (rl *RateLimiter) LimitHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		
		// 1. Identify rate-limiting key (defaulting to Client IP)
		ip, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			ip = r.RemoteAddr
		}
		
		// 2. Execute sliding window check via Lua script
		now := time.Now().UnixMilli()
		windowMillis := rl.windowSecs * 1000
		
		res, err := rl.redis.Eval(ctx, slidingWindowScript, []string{"rate_limit:" + ip}, now, windowMillis, rl.maxRequests)
		if err != nil {
			// Fail open on Redis connectivity outages to preserve availability
			next.ServeHTTP(w, r)
			return
		}

		// Assert Lua response
		allowed, ok := res.(int64)
		if !ok || allowed != 1 {
			w.Header().Set("Retry-After", strconv.Itoa(rl.windowSecs))
			http.Error(w, "Too Many Requests: API gateway rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}
