--!strict
--[[
    Per-player token-bucket rate limiter for remotes (ADR 0012). Pure: the clock is injected,
    so it loads under Lune and tests control time. One limiter per remote (or per class of
    remotes): `allow` spends tokens; a false return means "drop the request".
    Call `forget` on PlayerRemoving so buckets do not leak.
]]

export type Config = {
    -- Burst size: tokens a player holds when idle.
    capacity: number,
    -- Sustained rate: tokens regained per second.
    refillPerSecond: number,
    -- Seconds, monotonic (os.clock on the server).
    clock: () -> number,
}

export type RateLimiter = {
    -- Spends `cost` tokens (default 1) when available; false when the player is over budget.
    allow: (self: RateLimiter, userId: number, cost: number?) -> boolean,
    forget: (self: RateLimiter, userId: number) -> (),
}

type Bucket = { tokens: number, updatedAt: number }

local RateLimiterModule = {}

function RateLimiterModule.new(config: Config): RateLimiter
    assert(config.capacity > 0, "capacity must be positive")
    assert(config.refillPerSecond > 0, "refillPerSecond must be positive")
    local buckets: { [number]: Bucket } = {}

    local limiter: RateLimiter = {
        allow = function(_self: RateLimiter, userId: number, cost: number?): boolean
            local price = cost or 1
            local now = config.clock()
            local bucket = buckets[userId]
            if bucket == nil then
                bucket = { tokens = config.capacity, updatedAt = now }
                buckets[userId] = bucket
            end
            local elapsed = math.max(0, now - bucket.updatedAt)
            bucket.tokens =
                math.min(config.capacity, bucket.tokens + elapsed * config.refillPerSecond)
            bucket.updatedAt = now
            if price > bucket.tokens then
                return false
            end
            bucket.tokens -= price
            return true
        end,
        forget = function(_self: RateLimiter, userId: number)
            buckets[userId] = nil
        end,
    }
    return limiter
end

return RateLimiterModule
