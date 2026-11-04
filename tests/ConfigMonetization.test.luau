--!strict
local Config = require("../src/shared/Config")
local harness = require("./harness")

local function baseConfig(): Config.GameConfig
    return {
        gameName = "Test",
        sessionLockTimeoutSeconds = 60,
        autosaveIntervalSeconds = 30,
        purchaseLedgerSize = 50,
        saveConfirmTimeoutSeconds = 30,
        gamePasses = { { name = "VIP", id = 1 } },
        developerProducts = {
            { name = "Coins", id = 2, grant = { kind = "coins", amount = 100 } },
        },
    }
end

local function hasProblem(problems: { string }, fragment: string): boolean
    for _, problem in problems do
        if string.find(problem, fragment, 1, true) ~= nil then
            return true
        end
    end
    return false
end

return function(suite: harness.Harness)
    suite:test("every new surface is off by default and adds no problem", function()
        harness.isFalse(
            Config.default.rewardedAds ~= nil and Config.default.rewardedAds.enabled,
            "rewarded ads off"
        )
        harness.isFalse(
            Config.default.privateServers ~= nil and Config.default.privateServers.enabled,
            "private servers off"
        )
        harness.isFalse(
            Config.default.plusPrompt ~= nil and Config.default.plusPrompt.enabled,
            "plus prompt off"
        )
        harness.isFalse(
            Config.default.robuxTransfers ~= nil and Config.default.robuxTransfers.enabled,
            "transfers off"
        )
        harness.equal(#Config.validate(Config.default), 2, "still only the two unset ids")
    end)

    suite:test(
        "subscriptions: missing id, no benefits, duplicates and unknown legacy pass",
        function()
            local config = baseConfig()
            local unset: Config.SubscriptionConfig =
                { name = "A", subscriptionId = nil, benefits = {}, replacesPassName = "Nope" }
            local set: Config.SubscriptionConfig =
                { name = "A", subscriptionId = "EXP-1", benefits = { "x" }, replacesPassName = "VIP" }
            config.subscriptions = { unset, set }
            local problems = Config.validate(config)
            harness.isTrue(hasProblem(problems, "has no subscriptionId"), "id")
            harness.isTrue(hasProblem(problems, "has no benefits"), "benefits")
            harness.isTrue(hasProblem(problems, "declared twice"), "duplicate")
            harness.isTrue(hasProblem(problems, "unknown game pass"), "pass")
            harness.isTrue(hasProblem(problems, "subscriptionPollSeconds"), "poll interval")
        end
    )

    suite:test("a complete subscription config is valid", function()
        local config = baseConfig()
        config.subscriptionPollSeconds = 60
        local complete: Config.SubscriptionConfig =
            { name = "A", subscriptionId = "EXP-1", benefits = { "x" }, replacesPassName = "VIP" }
        config.subscriptions = { complete }
        harness.equal(#Config.validate(config), 0, "problems")
    end)

    suite:test("rewarded ads: only enabled config is checked, and every gap is reported", function()
        local config = baseConfig()
        config.rewardedAds = {
            enabled = false,
            disclosureLabel = "",
            dailyCap = 0,
            placements = {},
        }
        harness.equal(#Config.validate(config), 0, "disabled is not checked")
        config.rewardedAds = {
            enabled = true,
            disclosureLabel = "",
            dailyCap = 0,
            placements = {
                { name = "P", placementId = nil, rewardProduct = "Missing", label = "" },
                { name = "P", placementId = nil, rewardProduct = "Coins", label = "ok" },
            },
        }
        local problems = Config.validate(config)
        harness.isTrue(hasProblem(problems, "disclosureLabel"), "disclosure")
        harness.isTrue(hasProblem(problems, "dailyCap"), "cap")
        harness.isTrue(hasProblem(problems, "has no label"), "label")
        harness.isTrue(
            hasProblem(problems, "unknown developer product"),
            "reward must be a product"
        )
        harness.isTrue(hasProblem(problems, "declared twice"), "duplicate")
    end)

    suite:test("rewarded ads: enabled without placements is reported", function()
        local config = baseConfig()
        config.rewardedAds = {
            enabled = true,
            disclosureLabel = "ad",
            dailyCap = 1,
            placements = {},
        }
        harness.isTrue(hasProblem(Config.validate(config), "no placements"), "placements")
    end)

    suite:test("private servers: price, retries and setting bounds are validated", function()
        local config = baseConfig()
        config.privateServers = {
            enabled = true,
            expectedMonthlyPrice = 0,
            teleportRetries = -1,
            teleportRetryDelaySeconds = 0,
            settings = {
                { name = "maxPlayers", min = 10, max = 2, default = 5 },
                { name = "maxPlayers", min = 1, max = 4, default = 2 },
            },
        }
        local problems = Config.validate(config)
        harness.isTrue(hasProblem(problems, "expectedMonthlyPrice"), "price")
        harness.isTrue(hasProblem(problems, "teleportRetries"), "retries")
        harness.isTrue(hasProblem(problems, "teleportRetryDelaySeconds"), "delay")
        harness.isTrue(hasProblem(problems, "min <= default <= max"), "bounds")
        harness.isTrue(hasProblem(problems, "declared twice"), "duplicate")
    end)

    suite:test("plus prompt: placements, cooldown and cap are validated", function()
        local config = baseConfig()
        config.plusPrompt = {
            enabled = true,
            placements = { "menu", "menu" },
            cooldownSeconds = 0,
            maxPromptsPerSession = 0,
        }
        local problems = Config.validate(config)
        harness.isTrue(hasProblem(problems, "unique non-empty"), "placements")
        harness.isTrue(hasProblem(problems, "cooldownSeconds"), "cooldown")
        harness.isTrue(hasProblem(problems, "maxPromptsPerSession"), "cap")
        config.plusPrompt =
            { enabled = true, placements = {}, cooldownSeconds = 1, maxPromptsPerSession = 1 }
        harness.isTrue(hasProblem(Config.validate(config), "no placements"), "empty")
    end)

    suite:test("robux transfers: amounts stay inside the platform range", function()
        local config = baseConfig()
        config.robuxTransfers = { enabled = true, minAmount = 5, maxAmount = 600 }
        harness.isTrue(hasProblem(Config.validate(config), "robuxTransfers amounts"), "range")
        config.robuxTransfers = { enabled = true, minAmount = 100, maxAmount = 50 }
        harness.isTrue(hasProblem(Config.validate(config), "robuxTransfers amounts"), "order")
        config.robuxTransfers = { enabled = true, minAmount = 10.5, maxAmount = 500 }
        harness.isTrue(hasProblem(Config.validate(config), "integers"), "fraction")
        config.robuxTransfers = { enabled = true, minAmount = 10, maxAmount = 500 }
        harness.equal(#Config.validate(config), 0, "valid")
    end)
end
