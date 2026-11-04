--!strict
local CodesConfig = require("../../../src/shared/features/codes/CodesConfig")
local harness = require("../../harness")

local function base(): CodesConfig.CodesConfig
    return {
        maxCodeLength = 12,
        attemptCooldownSeconds = 1,
        failureThreshold = 5,
        entries = { { code = "ok-1", reward = { kind = "coins", amount = 5 } } },
    }
end

return function(suite: harness.Harness)
    suite:test("normalize trims and upper-cases", function()
        harness.equal(CodesConfig.normalize("  aBc "), "ABC")
    end)

    suite:test("a valid config has no problems", function()
        harness.equal(#CodesConfig.validate(base()), 0)
    end)

    suite:test("bad limits are each reported", function()
        local config = base()
        config.maxCodeLength = 0
        config.entries = {}
        config.attemptCooldownSeconds = 0
        config.failureThreshold = 1.5
        harness.equal(#CodesConfig.validate(config), 3)
    end)

    suite:test("empty, odd, long and duplicate codes are reported", function()
        local config = base()
        config.entries = {
            { code = " ", reward = { kind = "coins", amount = 5 } },
            { code = "has space", reward = { kind = "coins", amount = 5 } },
            { code = "WAYTOOLONGFORTHELIMIT", reward = { kind = "coins", amount = 5 } },
            { code = "dup", reward = { kind = "coins", amount = 5 } },
            { code = "DUP", reward = { kind = "coins", amount = 5 } },
        }
        harness.equal(#CodesConfig.validate(config), 4)
    end)

    suite:test("bad reward, expiry and redemptions are reported", function()
        local config = base()
        config.entries = {
            {
                code = "A",
                reward = { kind = "coins", amount = -1 },
                expiresAt = -5,
                maxRedemptions = 0,
            },
        }
        harness.equal(#CodesConfig.validate(config), 3)
    end)
end
