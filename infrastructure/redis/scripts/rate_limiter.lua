-- rate_limiter.lua
-- Atomic Sliding Window Rate Limiter using Redis Sorted Sets (ZSET).
--
-- KEYS[1]: The rate limit tracker key (e.g., 'nearby:rate:sliding:UUID:endpoint')
-- ARGV[1]: Current Unix epoch millisecond timestamp (integer)
-- ARGV[2]: Sliding window duration in milliseconds (e.g., 60000 for 1 minute)
-- ARGV[3]: Maximum allowed request token count within the window duration

local rate_key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])

-- Calculate the lower boundary of the sliding window
local clear_before = now - window

-- 1. Remove all logs representing requests that fell outside the current window
redis.call('ZREMRANGEBYSCORE', rate_key, 0, clear_before)

-- 2. Count requests currently recorded inside the active sliding window
local current_requests = redis.call('ZCARD', rate_key)

-- 3. Check if the client has capacity remaining
if current_requests < limit then
    -- Record the current request timestamp as both member and score
    -- Use client-provided random noise/UUID appending if sub-millisecond concurrency is expected,
    -- but standard timestamp is sufficient for sequential network requests.
    redis.call('ZADD', rate_key, now, now)
    
    -- Ensure the key's TTL matches the window duration to automatically garbage collect idle trackers
    redis.call('PEXPIRE', rate_key, window)
    
    -- Return 1 indicating the request is ALLOWED
    return 1
else
    -- Return 0 indicating the request is DENIED (rate limit breached)
    return 0
end
