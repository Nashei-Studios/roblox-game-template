--!strict
local TimeRewardsConfig = require("../../../src/shared/features/timerewards/TimeRewardsConfig")
local harness = require("../../harness")

local function base(): TimeRewardsConfig.TimeRewardsConfig
    return {
        graceHours = 6,
        daily = { { day = 1, reward = { kind = "coins", amount = 5 } } },
        sessionGifts = { { id = "a", afterMinutes = 5, reward = { kind = "coins", amount = 5 } } },
    }
end

return function(suite: harness.Harness)
    suite:test("a valid schedule has no problems", function()
        harness.equal(#TimeRewardsConfig.validate(base()), 0)
    end)

    suite:test("negative grace and an empty daily list are reported", function()
        local config = base()
        config.graceHours = -1
        config.daily = {}
        harness.equal(#TimeRewardsConfig.validate(config), 2)
    end)

    suite:test("days must be 1..N in order and rewards valid", function()
        local config = base()
        config.daily = {
            { day = 2, reward = { kind = "coins", amount = 5 } },
            { day = 3, reward = { kind = "coins", amount = 0 } },
        }
        harness.equal(#TimeRewardsConfig.validate(config), 3)
    end)

    suite:test("gift ids, timing and rewards are validated", function()
        local config = base()
        config.sessionGifts = {
            { id = "", afterMinutes = 0, reward = { kind = "coins", amount = 5 } },
            { id = "b", afterMinutes = 5, reward = { kind = "coins", amount = 5 } },
            { id = "b", afterMinutes = 5, reward = { kind = "coins", amount = -1 } },
        }
        harness.equal(#TimeRewardsConfig.validate(config), 4)
    end)
end
