--!strict
local RateLimiter = require("../../src/shared/net/RateLimiter")
local harness = require("../harness")

local function newLimiter(capacity: number, refill: number)
    local now = 0
    local limiter = RateLimiter.new({
        capacity = capacity,
        refillPerSecond = refill,
        clock = function(): number
            return now
        end,
    })
    local function advance(seconds: number)
        now += seconds
    end
    return limiter, advance
end

return function(suite: harness.Harness)
    suite:test("allows a burst up to capacity then refuses", function()
        local limiter = newLimiter(3, 1)
        harness.isTrue(limiter:allow(1), "first")
        harness.isTrue(limiter:allow(1), "second")
        harness.isTrue(limiter:allow(1), "third")
        harness.isFalse(limiter:allow(1), "fourth over budget")
    end)

    suite:test("tokens refill with time but never above capacity", function()
        local limiter, advance = newLimiter(2, 1)
        limiter:allow(1)
        limiter:allow(1)
        harness.isFalse(limiter:allow(1), "empty")
        advance(1)
        harness.isTrue(limiter:allow(1), "one token regained")
        harness.isFalse(limiter:allow(1), "only one regained")
        advance(100)
        harness.isTrue(limiter:allow(1), "refilled")
        harness.isTrue(limiter:allow(1), "refilled to capacity")
        harness.isFalse(limiter:allow(1), "capped at capacity")
    end)

    suite:test("players have independent buckets", function()
        local limiter = newLimiter(1, 1)
        harness.isTrue(limiter:allow(1), "player 1")
        harness.isFalse(limiter:allow(1), "player 1 exhausted")
        harness.isTrue(limiter:allow(2), "player 2 unaffected")
    end)

    suite:test("an expensive request can exceed the remaining budget", function()
        local limiter = newLimiter(5, 1)
        harness.isFalse(limiter:allow(1, 6), "cost above capacity is never allowed")
        harness.isTrue(limiter:allow(1, 5), "cost equal to capacity")
        harness.isFalse(limiter:allow(1, 1), "drained")
    end)

    suite:test("forget resets a player so buckets do not leak", function()
        local limiter = newLimiter(1, 1)
        limiter:allow(1)
        harness.isFalse(limiter:allow(1), "exhausted")
        limiter:forget(1)
        harness.isTrue(limiter:allow(1), "fresh bucket after forget")
    end)

    suite:test("a clock that goes backwards does not mint tokens", function()
        local limiter, advance = newLimiter(1, 1)
        advance(10)
        limiter:allow(1)
        advance(-5)
        harness.isFalse(limiter:allow(1), "no refill from negative time")
    end)
end
