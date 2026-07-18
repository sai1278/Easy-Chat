-- acquire_lock.lua
-- Re-entrant Distributed Lock Acquisition Script.
--
-- KEYS[1]: Base lock key (e.g., 'nearby:lock:chat_room:UUID')
-- ARGV[1]: Lock Owner Unique Token (cryptographic UUID representing the client)
-- ARGV[2]: Lease time in milliseconds (PX expiration duration)

local lock_key = KEYS[1]
local count_key = KEYS[1] .. ":count"
local owner = ARGV[1]
local lease = tonumber(ARGV[2])

-- 1. If lock is free, set owner and init re-entry count to 1
if redis.call("EXISTS", lock_key) == 0 then
    redis.call("SET", lock_key, owner, "PX", lease)
    redis.call("SET", count_key, 1, "PX", lease)
    return 1 -- Lock acquired successfully
end

-- 2. If lock is already held, verify ownership to support re-entrant recursion
if redis.call("GET", lock_key) == owner then
    redis.call("INCR", count_key)
    -- Extend lease life for both keys to prevent mid-operation expiration
    redis.call("PEXPIRE", lock_key, lease)
    redis.call("PEXPIRE", count_key, lease)
    return 1 -- Lock re-entered successfully
else
    -- Lock held by a different client
    return 0
end
