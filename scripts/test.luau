--!strict
--[[
    Test runner. Run with: lune run scripts/test
    Add each new test file to `suites` (explicit list keeps the runner strictly typed).
]]

local process = require("@lune/process")

local harness = require("../tests/harness")

local suites: { { name: string, register: (suite: harness.Harness) -> () } } = {
    { name = "Config", register = require("../tests/Config.test") },
    { name = "Analytics", register = require("../tests/Analytics.test") },
    { name = "Monetization", register = require("../tests/Monetization.test") },
    { name = "Session", register = require("../tests/Session.test") },
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
