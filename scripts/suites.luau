--!strict
--[[
    Runtime-neutral test runner: no Lune API, so it loads under both Lune and the Luau CLI
    (ADR 0017). Add each new test file to `suites` (explicit list keeps it strictly typed).
    Entry points: `scripts/test.luau` (Lune, `lune run scripts/test`) and
    `scripts/test_luau.luau` (`luau --coverage scripts/test_luau.luau`, see scripts/coverage.ps1).
]]

local harness = require("../tests/harness")

local suites: { { name: string, register: (suite: harness.Harness) -> () } } = {
    { name = "Config", register = require("../tests/Config.test") },
    { name = "Result", register = require("../tests/Result.test") },
    { name = "Analytics", register = require("../tests/features/analytics/Analytics.test") },
    {
        name = "AnalyticsTracker",
        register = require("../tests/features/analytics/AnalyticsTracker.test"),
    },
    { name = "Flags", register = require("../tests/features/flags/Flags.test") },
    {
        name = "ReceiptDelivery",
        register = require("../tests/features/monetization/ReceiptDelivery.test"),
    },
    {
        name = "ProductGrants",
        register = require("../tests/features/monetization/ProductGrants.test"),
    },
    {
        name = "PlayerDataMigrations",
        register = require("../tests/features/playerdata/PlayerDataMigrations.test"),
    },
    {
        name = "Monetization",
        register = require("../tests/features/monetization/Monetization.test"),
    },
    {
        name = "InMemoryProfileRepository (port contract)",
        register = require("../tests/features/playerdata/InMemoryProfileRepository.test"),
    },
    {
        name = "PlayerDataService",
        register = require("../tests/features/playerdata/PlayerDataService.test"),
    },
    {
        name = "AnalyticsServiceSink (adapter)",
        register = require("../tests/adapters/AnalyticsServiceSink.test"),
    },
    {
        name = "ConfigServiceFlags (adapter)",
        register = require("../tests/adapters/ConfigServiceFlags.test"),
    },
    {
        name = "ProfileStoreRepository (adapter)",
        register = require("../tests/adapters/ProfileStoreRepository.test"),
    },
    { name = "Validation", register = require("../tests/net/Validation.test") },
    { name = "RateLimiter", register = require("../tests/net/RateLimiter.test") },
    {
        name = "PurchaseRequests",
        register = require("../tests/features/monetization/PurchaseRequests.test"),
    },
    { name = "RemoteBudget", register = require("../tests/perf/RemoteBudget.test") },
    { name = "ProbeEvaluator", register = require("../tests/perf/ProbeEvaluator.test") },
    {
        name = "ChargeMeter",
        register = require("../tests/features/keysprint/ChargeMeter.test"),
    },
    {
        name = "StageLayout",
        register = require("../tests/features/keysprint/StageLayout.test"),
    },
    {
        name = "StageRuns",
        register = require("../tests/features/keysprint/StageRuns.test"),
    },
    {
        name = "Progression",
        register = require("../tests/features/keysprint/Progression.test"),
    },
    {
        name = "Funnel",
        register = require("../tests/features/keysprint/Funnel.test"),
    },
    {
        name = "PressBatcher",
        register = require("../tests/features/keysprint/PressBatcher.test"),
    },
    {
        name = "HudModel",
        register = require("../tests/features/keysprint/HudModel.test"),
    },
    {
        name = "KeySprintController",
        register = require("../tests/features/keysprint/KeySprintController.test"),
    },
    {
        name = "StudioLockPolicy (hook)",
        register = require("../tests/claude/StudioLockPolicy.test"),
    },
}

local Suites = {}

--- Runs every suite, printing results. Returns (passed, failed).
function Suites.run(): (number, number)
    local totalPassed, totalFailed = 0, 0
    for _, entry in suites do
        print(entry.name)
        local suite = harness.new()
        entry.register(suite)
        local passed, failed = suite:run()
        totalPassed += passed
        totalFailed += failed
    end
    print(`\n{totalPassed} passed, {totalFailed} failed`)
    return totalPassed, totalFailed
end

return Suites
