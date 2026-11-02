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
            developerProducts = { { name = "Coins", id = 222 } },
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
            developerProducts = { { name = "Coins", id = 222 } },
        }
        local found = Config.findProductById(config, 222)
        harness.isTrue(found ~= nil and found.name == "Coins", "found Coins")
        harness.isTrue(Config.findProductById(config, 999) == nil, "unknown id")
    end)
end
