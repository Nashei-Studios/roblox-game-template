--!strict
local SessionGifts = require("../../../src/shared/features/timerewards/SessionGifts")
local TimeRewardsConfig = require("../../../src/shared/features/timerewards/TimeRewardsConfig")
local harness = require("../../harness")

local gifts: { TimeRewardsConfig.SessionGift } = {
    { id = "five", afterMinutes = 5, reward = { kind = "coins", amount = 10 } },
}

local function reasonOf(check: SessionGifts.Check): string
    if check.ok then
        return "ok"
    end
    return check.reason
end

return function(suite: harness.Harness)
    suite:test("a gift is not ready before its time", function()
        harness.equal(reasonOf(SessionGifts.check(gifts, "five", 1000, 1299, {})), "not_ready")
    end)

    suite:test("a gift is ready exactly at its time", function()
        harness.equal(reasonOf(SessionGifts.check(gifts, "five", 1000, 1300, {})), "ok")
    end)

    suite:test("a claimed gift is not offered twice", function()
        harness.equal(
            reasonOf(SessionGifts.check(gifts, "five", 1000, 5000, { five = true })),
            "already_claimed"
        )
    end)

    suite:test("an unknown id is refused", function()
        harness.equal(reasonOf(SessionGifts.check(gifts, "nope", 1000, 5000, {})), "unknown_gift")
    end)

    suite:test("a clock before the join time makes nothing ready", function()
        harness.equal(reasonOf(SessionGifts.check(gifts, "five", 1000, 500, {})), "not_ready")
    end)
end
