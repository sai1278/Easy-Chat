-- release_lock.lua
-- Re-entrant Distributed Lock Release Script.
--
-- KEYS[1]: Base lock key (e.g., 'nearby:lock:chat_room:UUID')
-- ARGV[1]: Lock Owner Unique Token (must match token generated on acquisition)

local lock_key = KEYS[1]
local count_key = KEYS[1] .. ":count"
local owner = ARGV[1]

-- 1. Assert ownership before executing release
if redis.call("GET", lock_key) ~= owner then
    return 0 -- Failed release: client does not own the lock
end

-- 2. Decrement re-entry index counter
local count = redis.call("DECR", count_key)

-- 3. If recursion has finished (count is 0 or less), execute hard delete
if count <= 0 then
    redis.call("DEL", lock_key)
    redis.call("DEL", count_key)
    return 1 -- Lock fully released and deleted
else
    -- Lock remains active, but recursion depth was reduced
    return 2
end
