--!strict
--[[
    Lune entry point: `lune run scripts/perf-budget [schema]` (default net/schema.zap).
    Prints the worst-case remote bandwidth per player and exits 1 when a remote or the total is
    over the budget in src/shared/perf/PerfBudget.luau (ADR 0019). The logic is in
    src/shared/perf/RemoteBudget (pure, tested); this file only reads the schema and reports.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local PerfBudget = require("../src/shared/perf/PerfBudget")
local PodiumConfig = require("../src/shared/features/podium/PodiumConfig")
local RarityConfig = require("../src/shared/features/rarity/RarityConfig")
local RemoteBudget = require("../src/shared/perf/RemoteBudget")

local schemaPath = process.args[1] or "net/schema.zap"
local parsed = RemoteBudget.parseSchema(fs.readFile(schemaPath))
if not parsed.ok then
    print(`perf-budget: cannot read {schemaPath}: {parsed.error}`)
    process.exit(1)
end
local events = if parsed.ok then parsed.value else {}

local report = RemoteBudget.evaluate(events, PerfBudget)
print("remote            from    payload  event  events/s  bytes/s")
for _, row in report.rows do
    print(
        string.format(
            "%-17s %-7s %7d %6d %9.1f %8.1f",
            row.name,
            row.from,
            row.payloadBytes,
            row.eventBytes,
            row.eventsPerSecond,
            row.bytesPerSecond
        )
    )
end
print(
    `client -> server: {report.clientToServerBytesPerSecond} B/s of {PerfBudget.clientToServerBytesPerSecond}`
)
print(
    `server -> client: {report.serverToClientBytesPerSecond} B/s of {PerfBudget.serverToClientBytesPerSecond}`
)
-- World podium (ADR 0055): the configured refresh must respect the budget floor.
local podiumBudget = PerfBudget.podium
local podiumConfig = Config.default.podium
if podiumBudget ~= nil and podiumConfig ~= nil then
    local problems = PodiumConfig.problems(
        podiumConfig,
        Config.default.rarity or RarityConfig.default,
        podiumBudget.minRefreshSeconds
    )
    for _, problem in problems do
        table.insert(report.failures, problem)
    end
    print(
        `podium: refresh {podiumConfig.refreshSeconds}s (min {podiumBudget.minRefreshSeconds}s), parts cap {podiumBudget.maxParts}`
    )
end
if #report.failures > 0 then
    for _, failure in report.failures do
        print(`FAIL {failure}`)
    end
    process.exit(1)
end
print("perf-budget: OK")
