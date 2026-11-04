--!strict
local Notifier = require("../../../src/shared/ports/Notifier")
local TimeRewardRequests = require("../../../src/shared/features/timerewards/TimeRewardRequests")
local TimeRewards = require("../../../src/shared/ports/TimeRewards")
local harness = require("../../harness")

type Fixture = {
    handler: TimeRewardRequests.TimeRewardRequests,
    kinds: { string },
    claims: { string },
}

local function newFixture(allowed: boolean, outcome: TimeRewards.ClaimResult): Fixture
    local kinds: { string } = {}
    local claims: { string } = {}
    local service: TimeRewards.TimeRewards = {
        startSession = function(_self: TimeRewards.TimeRewards, _userId: number) end,
        claimDaily = function(_self: TimeRewards.TimeRewards, _userId: number)
            table.insert(claims, "daily")
            return outcome
        end,
        claimSession = function(_self: TimeRewards.TimeRewards, _userId: number, giftId: string)
            table.insert(claims, giftId)
            return outcome
        end,
        forget = function(_self: TimeRewards.TimeRewards, _userId: number) end,
    }
    local notifier: Notifier.Notifier = {
        notify = function(
            _self: Notifier.Notifier,
            _userId: number,
            kind: string,
            _amount: number
        ): Notifier.NotifyError?
            table.insert(kinds, kind)
            return nil
        end,
    }
    local handler = TimeRewardRequests.new({
        timeRewards = service,
        notifier = notifier,
        allowDaily = function(_userId: number): boolean
            return allowed
        end,
        allowSession = function(_userId: number): boolean
            return allowed
        end,
        giftIds = { "five" },
    })
    return { handler = handler, kinds = kinds, claims = claims }
end

return function(suite: harness.Harness)
    suite:test("rate-limited requests never reach the port", function()
        local fixture = newFixture(false, { ok = true, value = { amount = 1 } })
        harness.isFalse(fixture.handler:handleDaily(1).ok)
        harness.isFalse(fixture.handler:handleSession(1, "five").ok)
        harness.equal(#fixture.claims, 0)
        harness.equal(#fixture.kinds, 0)
    end)

    suite:test("a daily success notifies daily_claimed", function()
        local fixture = newFixture(true, { ok = true, value = { amount = 5, streak = 1 } })
        harness.isTrue(fixture.handler:handleDaily(1).ok, "accepted")
        harness.equal(fixture.kinds[1], "daily_claimed")
    end)

    suite:test("a daily failure notifies daily_unavailable", function()
        local fixture = newFixture(true, { ok = false, error = "already_claimed" })
        harness.isFalse(fixture.handler:handleDaily(1).ok)
        harness.equal(fixture.kinds[1], "daily_unavailable")
    end)

    suite:test("an id outside Config is rejected before the port", function()
        local fixture = newFixture(true, { ok = true, value = { amount = 1 } })
        harness.isFalse(fixture.handler:handleSession(1, "hack").ok)
        harness.isFalse(fixture.handler:handleSession(1, 5).ok)
        harness.equal(#fixture.claims, 0)
    end)

    suite:test("session success and failure map to their toasts", function()
        local good = newFixture(true, { ok = true, value = { amount = 1 } })
        harness.isTrue(good.handler:handleSession(1, "five").ok, "accepted")
        harness.equal(good.kinds[1], "session_gift_claimed")
        local bad = newFixture(true, { ok = false, error = "not_ready" })
        harness.isFalse(bad.handler:handleSession(1, "five").ok)
        harness.equal(bad.kinds[1], "session_gift_unavailable")
    end)
end
