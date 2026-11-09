--!strict
local Config = require("../../../src/shared/Config")
local LeaderboardsConfig = require("../../../src/shared/features/leaderboards/LeaderboardsConfig")
local MilestoneTracker = require("../../../src/shared/features/progress/MilestoneTracker")
local PlayerStats = require("../../../src/shared/features/leaderboards/PlayerStats")
local ProgressRules = require("../../../src/shared/features/progress/ProgressRules")
local harness = require("../../harness")

local TIERS: { ProgressRules.Tier } = {
    { min = 0, name = "Novice", colorHex = "#C9C9C9" },
    { min = 1, name = "Adept", colorHex = "#9FE8B0" },
    { min = 3, name = "Expert", colorHex = "#6FC3FF" },
    { min = 10, name = "Master", colorHex = "#FFD84A" },
}

return function(suite: harness.Harness)
    suite:test("a tier is the last whose minimum is reached", function()
        harness.equal(ProgressRules.tierFor(0, TIERS).name, "Novice", "lowest")
        harness.equal(ProgressRules.tierFor(2, TIERS).name, "Adept", "between")
        harness.equal(ProgressRules.tierFor(3, TIERS).name, "Expert", "exact")
        harness.equal(ProgressRules.tierFor(99, TIERS).name, "Master", "above the last")
    end)

    suite:test("tiers are validated", function()
        harness.equal(#ProgressRules.validateTiers(TIERS), 0, "valid")
        harness.equal(#ProgressRules.validateTiers({}), 1, "empty")
        local bad: { ProgressRules.Tier } = {
            { min = 5, name = "", colorHex = "red" },
            { min = 5, name = "B", colorHex = "#FFFFFF" },
        }
        harness.equal(#ProgressRules.validateTiers(bad), 3, "name, color and order")
    end)

    suite:test("a milestone is the highest multiple of the step newly reached", function()
        harness.equal(ProgressRules.milestoneCrossed(40, 55, 50), 50, "crossed")
        harness.equal(ProgressRules.milestoneCrossed(50, 99, 50), nil, "same band")
        harness.equal(ProgressRules.milestoneCrossed(50, 205, 50), 200, "skips to the highest")
        harness.equal(ProgressRules.milestoneCrossed(0, 10, 50), nil, "none yet")
        harness.equal(ProgressRules.milestoneCrossed(0, 100, 0), nil, "no step")
    end)

    suite:test("messages fill name and value from a template", function()
        harness.equal(
            ProgressRules.format("{name} reached {value}!", "Ana", 150),
            "Ana reached 150!",
            "both"
        )
        harness.equal(ProgressRules.format("{value}", "%1", 7), "7", "no pattern leak")
        harness.equal(ProgressRules.format("hi {name}", "%1", 7), "hi %1", "name is literal")
    end)

    suite:test(
        "the tracker sets the baseline on first sight and announces each band once",
        function()
            local tracker = MilestoneTracker.new(50)
            harness.equal(tracker:observe(1, 320), nil, "joining high never announces")
            harness.equal(tracker:observe(1, 340), nil, "same band")
            harness.equal(tracker:observe(1, 355), 350, "new band")
            harness.equal(tracker:observe(1, 360), nil, "announced once")
            harness.equal(tracker:observe(2, 10), nil, "another player has own baseline")
            tracker:forget(1)
            harness.equal(tracker:observe(1, 900), nil, "after forget the baseline resets")
        end
    )

    suite:test(
        "a daily count comes from the lifetime counter and resets at UTC midnight",
        function()
            local daily = ProgressRules.newDailyCounter()
            harness.equal(daily:observe(1, 100, 1000), 0, "baseline")
            harness.equal(daily:observe(1, 160, 2000), 60, "counted")
            harness.equal(daily:observe(1, 170, 86400 + 5), 0, "next day restarts")
            harness.equal(daily:observe(1, 90, 86400 + 6), 0, "never negative")
            daily:forget(1)
            harness.equal(daily:observe(1, 500, 86400 + 7), 0, "forget restarts")
        end
    )

    suite:test("a daily board needs one extra stat and one board line", function()
        local config = table.clone(assert(Config.default.leaderboards, "leaderboards config"))
        config.extraStats = { "actionsToday" }
        config.boards = table.clone(config.boards)
        config.boards.ActionsToday =
            { stat = "actionsToday", refreshSeconds = 300, size = 10, resetCycle = "daily" }
        harness.equal(
            #LeaderboardsConfig.validate(config),
            0,
            table.concat(LeaderboardsConfig.validate(config), "; ")
        )
        local profile: PlayerStats.StatProfile = { coins = 0, sessionCount = 0 }
        local extra: PlayerStats.ExtraStats = { actionsToday = 42.9 }
        harness.equal(PlayerStats.read(profile, "actionsToday", extra), 42, "read")
        harness.isTrue(PlayerStats.read(profile, "other", extra) == nil, "unknown extra")
        harness.isTrue(PlayerStats.read(profile, "actionsToday") == nil, "no extra given")
        config.extraStats = nil
        harness.isTrue(#LeaderboardsConfig.validate(config) >= 1, "unknown without extraStats")
        config.extraStats = { "coins" }
        harness.isTrue(#LeaderboardsConfig.validate(config) >= 1, "repeats a built-in")
    end)
end
