--!strict
local Config = require("../src/shared/Config")
local KeySprintRules = require("../src/shared/features/keysprint/KeySprintRules")
local harness = require("./harness")

return function(suite: harness.Harness)
    suite:test("default config reports every unset id", function()
        local problems = Config.validate(Config.default)
        harness.equal(#problems, 4, "problem count")
    end)

    suite:test("a fully configured game has no problems", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 30,
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
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 30,
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
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 30,
            gamePasses = {},
            developerProducts = {
                { name = "Coins", id = 222, grant = { kind = "coins", amount = 100 } },
            },
        }
        local found = Config.findProductById(config, 222)
        harness.isTrue(found ~= nil and found.name == "Coins", "found Coins")
        harness.isTrue(Config.findProductById(config, 999) == nil, "unknown id")
    end)

    suite:test("findProductByName matches only configured names", function()
        local found = Config.findProductByName(Config.default, "Coins100")
        harness.isTrue(found ~= nil and found.name == "Coins100", "found Coins100")
        harness.isTrue(Config.findProductByName(Config.default, "Nope") == nil, "unknown name")
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
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 30,
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

    suite:test("a ledger window below 1 or fractional is rejected", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            purchaseLedgerSize = 0,
            saveConfirmTimeoutSeconds = 30,
            gamePasses = {},
            developerProducts = {},
        }
        harness.equal(#Config.validate(config), 1, "zero")
        config.purchaseLedgerSize = 2.5
        harness.equal(#Config.validate(config), 1, "fraction")
    end)

    suite:test("a non-positive save confirmation timeout is rejected", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 0,
            gamePasses = {},
            developerProducts = {},
        }
        harness.equal(#Config.validate(config), 1, "problem count")
    end)

    suite:test("default config declares 2 passes and 2 products with no ids", function()
        harness.equal(#Config.default.gamePasses, 2, "passes")
        harness.equal(#Config.default.developerProducts, 2, "products")
        for _, pass in Config.default.gamePasses do
            harness.isTrue(pass.id == nil, `{pass.name} id is a TODO, never invented`)
        end
        for _, product in Config.default.developerProducts do
            harness.isTrue(product.id == nil, `{product.name} id is a TODO, never invented`)
        end
    end)

    suite:test("default config names the key sprint monetization items", function()
        harness.equal(Config.default.gamePasses[1].name, "FasterCharge", "pass 1")
        harness.equal(Config.default.gamePasses[2].name, "Trail", "pass 2")
        local skip = Config.grantsByName(Config.default)["SkipStage"]
        harness.isTrue(skip ~= nil and skip.kind == "skipStage", "skip grant")
        if skip ~= nil and skip.kind == "skipStage" then
            harness.equal(skip.maxStage, KeySprintRules.STAGE_COUNT, "maxStage")
        end
    end)

    suite:test("validate rejects a skipStage grant with a bad maxStage", function()
        local config: Config.GameConfig = {
            gameName = "Test",
            sessionLockTimeoutSeconds = 60,
            autosaveIntervalSeconds = 30,
            purchaseLedgerSize = 50,
            saveConfirmTimeoutSeconds = 30,
            gamePasses = {},
            developerProducts = {
                { name = "Skip", id = 5, grant = { kind = "skipStage", maxStage = 0 } },
            },
        }
        harness.equal(#Config.validate(config), 1, "problem count")
    end)
end
