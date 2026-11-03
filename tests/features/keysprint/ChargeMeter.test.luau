--!strict
local ChargeMeter = require("../../../src/shared/features/keysprint/ChargeMeter")
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local RateLimiter = require("../../../src/shared/net/RateLimiter")
local harness = require("../../harness")

local function newMeter()
    local now = 0
    local function clock(): number
        return now
    end
    local meter = ChargeMeter.new({
        clock = clock,
        pressLimiter = RateLimiter.new({
            capacity = KeySprintRules.PRESS_BURST,
            refillPerSecond = KeySprintRules.MAX_PRESSES_PER_SECOND,
            clock = clock,
        }),
    })
    local function advance(seconds: number)
        now += seconds
    end
    return meter, advance
end

local function multiplierOf(result: ChargeMeter.PressResult): number
    if result.ok then
        return result.multiplier
    end
    return -1
end

local function reasonOf(result: ChargeMeter.PressResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("a new player is at multiplier 1", function()
        local meter = newMeter()
        harness.equal(meter:multiplier(1, 5), 1, "idle")
    end)

    suite:test("accepted presses raise the multiplier by CHARGE_PER_PRESS each", function()
        local meter = newMeter()
        local result = meter:press(1, 10, 5)
        harness.isTrue(result.ok, "accepted")
        harness.isTrue(
            math.abs(multiplierOf(result) - (1 + 10 * KeySprintRules.CHARGE_PER_PRESS)) < 1e-9,
            "multiplier"
        )
    end)

    suite:test("the multiplier never exceeds the player's cap", function()
        local meter, advance = newMeter()
        local last = 0
        for _ = 1, 40 do
            last = multiplierOf(meter:press(1, 12, 3))
            advance(1.2)
        end
        harness.equal(last, 3, "clipped to cap 3")
    end)

    suite:test("a lower cap clips existing charge on read", function()
        local meter = newMeter()
        meter:press(1, 12, 30)
        harness.isTrue(meter:multiplier(1, 30) > 2, "charged")
        harness.equal(meter:multiplier(1, 2), 2, "cap 2")
    end)

    suite:test("a batch beyond the press rate limit is refused whole", function()
        local meter = newMeter()
        harness.equal(reasonOf(meter:press(1, 12, 5)), "ok", "first batch")
        harness.equal(reasonOf(meter:press(1, 12, 5)), "rate_limited", "second batch same instant")
    end)

    suite:test(
        "the server rate, not the batch size the client claims, bounds the charge",
        function()
            local meter, advance = newMeter()
            local accepted = 0
            for _ = 1, 20 do
                if meter:press(1, 12, 30).ok then
                    accepted += 12
                end
                advance(0.25)
            end
            -- 5 s at 10 presses/s plus a burst of 16 is at most 66 presses; the client claimed 240.
            harness.isTrue(accepted <= 12 * 6, "accepted presses bounded")
        end
    )

    suite:test("invalid batch sizes are rejected before they cost tokens", function()
        local meter = newMeter()
        harness.equal(reasonOf(meter:press(1, 0, 5)), "out_of_range", "zero")
        harness.equal(reasonOf(meter:press(1, 13, 5)), "out_of_range", "above max")
        harness.equal(reasonOf(meter:press(1, 1.5, 5)), "not_an_integer", "fraction")
        harness.equal(reasonOf(meter:press(1, "9", 5)), "not_a_number", "string")
        harness.equal(reasonOf(meter:press(1, 0 / 0, 5)), "not_finite", "nan")
        harness.equal(reasonOf(meter:press(1, 12, 5)), "ok", "full bucket still there")
    end)

    suite:test("charge decays while idle and never goes below 1", function()
        local meter, advance = newMeter()
        meter:press(1, 10, 5)
        advance(2)
        local expected = 1
            + 10 * KeySprintRules.CHARGE_PER_PRESS
            - 2 * KeySprintRules.DECAY_PER_SECOND
        harness.isTrue(math.abs(meter:multiplier(1, 5) - expected) < 1e-9, "decayed")
        advance(100)
        harness.equal(meter:multiplier(1, 5), 1, "floor")
    end)

    suite:test("the Faster charge pass adds more per press but stays under the cap", function()
        local plain = newMeter()
        local fast = newMeter()
        fast:setFasterCharge(1, true)
        plain:press(1, 4, 5)
        fast:press(1, 4, 5)
        harness.isTrue(fast:multiplier(1, 5) > plain:multiplier(1, 5), "faster")
        local capped = newMeter()
        capped:setFasterCharge(1, true)
        capped:press(1, 12, 1.5)
        harness.equal(capped:multiplier(1, 1.5), 1.5, "still cap")
    end)

    suite:test("players are independent and forget clears state", function()
        local meter = newMeter()
        meter:press(1, 10, 5)
        harness.equal(meter:multiplier(2, 5), 1, "other player")
        meter:forget(1)
        harness.equal(meter:multiplier(1, 5), 1, "forgotten")
    end)

    suite:test("reset drops the charge but keeps the pass", function()
        local meter = newMeter()
        meter:setFasterCharge(1, true)
        meter:press(1, 10, 5)
        meter:reset(1)
        harness.equal(meter:multiplier(1, 5), 1, "reset")
        meter:press(1, 4, 5)
        local expected = 1
            + 4 * KeySprintRules.CHARGE_PER_PRESS * KeySprintRules.FASTER_CHARGE_FACTOR
        harness.isTrue(math.abs(meter:multiplier(1, 5) - expected) < 1e-9, "pass kept")
    end)
end
