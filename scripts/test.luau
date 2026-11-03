--!strict
--[[
    Test runner. Run with: lune run scripts/test
    Add each new test file to `suites` (explicit list keeps the runner strictly typed).
]]

local process = require("@lune/process")

local harness = require("../tests/harness")

local suites: { { name: string, register: (suite: harness.Harness) -> () } } = {
    { name = "Config", register = require("../tests/Config.test") },
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
}

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
if totalFailed > 0 then
    process.exit(1)
end
