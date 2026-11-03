--!strict
local Config = require("../src/shared/Config")
local harness = require("./harness")

return function(suite: harness.Harness)
    suite:test("default config reports every unset id", function()
        local problems = Config.validate(Config.default)
        harness.equal(#problems, 2, "problem count")
    end)

    suite:test("a fully configured game has no problems", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            gamePasses = { { name = "VIP", id = 111 } },
            developerProducts = {
                { name = "Coins", id = 222, grant = { kind = "coins", amount = 100 } },
            },
        }
        harness.equal(#Config.validate(config), 0, "problem count")
    end)

    suite:test("non-positive timings are rejected", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 0,
            autosaveIntervalSeconds = -1,
            gamePasses = {},
            developerProducts = {},
        }
        harness.equal(#Config.validate(config), 2, "problem count")
    end)

    suite:test("findProductById matches only configured ids", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            gamePasses = {},
            developerProducts = {
                { name = "Coins", id = 222, grant = { kind = "coins", amount = 100 } },
            },
        }
        local found = Config.findProductById(config, 222)
        harness.isTrue(found ~= nil and found.name == "Coins", "found Coins")
        harness.isTrue(Config.findProductById(config, 999) == nil, "unknown id")
    end)

    suite:test("default config declares what Coins100 delivers", function()
        local grants = Config.grantsByName(Config.default)
        local coins = grants["Coins100"]
        harness.isTrue(coins ~= nil and coins.kind == "coins" and coins.amount == 100, "Coins100")
    end)

    suite:test("invalid product grants are reported", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            gamePasses = {},
            developerProducts = {
                { name = "Zero", id = 1, grant = { kind = "coins", amount = 0 } },
                { name = "Fraction", id = 2, grant = { kind = "coins", amount = 2.5 } },
                { name = "Dupe", id = 3, grant = { kind = "coins", amount = 1 } },
                { name = "Dupe", id = 4, grant = { kind = "coins", amount = 1 } },
            },
        }
        harness.equal(#Config.validate(config), 3, "problem count")
    end)
end
