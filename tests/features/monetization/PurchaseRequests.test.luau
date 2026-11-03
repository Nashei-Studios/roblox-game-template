--!strict
local PurchaseRequests = require("../../../src/shared/features/monetization/PurchaseRequests")
local RateLimiter = require("../../../src/shared/net/RateLimiter")
local harness = require("../../harness")

type Fixture = {
    handler: PurchaseRequests.PurchaseRequests,
    prompts: { string },
    advance: (seconds: number) -> (),
}

local function newFixture(promptSucceeds: boolean): Fixture
    local now = 0
    local limiter = RateLimiter.new({
        capacity = 2,
        refillPerSecond = 1,
        clock = function(): number
            return now
        end,
    })
    local prompts: { string } = {}
    local handler = PurchaseRequests.new({
        productNames = { "Coins100" },
        allow = function(userId: number): boolean
            return limiter:allow(userId)
        end,
        prompt = function(_userId: number, productName: string): boolean
            table.insert(prompts, productName)
            return promptSucceeds
        end,
    })
    return {
        handler = handler,
        prompts = prompts,
        advance = function(seconds: number)
            now += seconds
        end,
    }
end

local function reasonOf(result: PurchaseRequests.HandleResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("a valid request opens the prompt for that product", function()
        local fixture = newFixture(true)
        local result = fixture.handler:handle(1, "Coins100")
        harness.equal(reasonOf(result), "ok", "accepted")
        harness.equal(#fixture.prompts, 1, "one prompt")
        harness.equal(fixture.prompts[1], "Coins100", "product")
    end)

    suite:test("an unknown product is rejected and never prompts", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.handler:handle(1, "FreeEverything")), "not_allowed")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("malformed payloads that slip past the generated layer are rejected", function()
        local fixture = newFixture(true)
        local nan: number = 0 / 0
        harness.equal(reasonOf(fixture.handler:handle(1, nil)), "not_a_string", "nil")
        harness.equal(reasonOf(fixture.handler:handle(2, 100)), "not_a_string", "number")
        harness.equal(reasonOf(fixture.handler:handle(3, nan)), "not_a_string", "NaN")
        harness.equal(reasonOf(fixture.handler:handle(4, math.huge)), "not_a_string", "inf")
        harness.equal(reasonOf(fixture.handler:handle(5, { "Coins100" })), "not_a_string", "table")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("requests over the budget are dropped before validation", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.handler:handle(1, "Coins100")), "ok", "first")
        harness.equal(reasonOf(fixture.handler:handle(1, "Coins100")), "ok", "second")
        -- Even a garbage payload reports rate_limited: the limiter runs first.
        harness.equal(reasonOf(fixture.handler:handle(1, nil)), "rate_limited", "third")
        harness.equal(#fixture.prompts, 2, "only the first two prompted")
        harness.equal(reasonOf(fixture.handler:handle(2, "Coins100")), "ok", "other player")
        fixture.advance(1)
        harness.equal(reasonOf(fixture.handler:handle(1, "Coins100")), "ok", "refilled")
    end)

    suite:test("a prompt that cannot open is reported, not hidden", function()
        local fixture = newFixture(false)
        harness.equal(reasonOf(fixture.handler:handle(1, "Coins100")), "prompt_failed")
    end)
end
