--!strict
--[[
    Lune entry point: `lune run scripts/perf-budget [schema] [placeCounts]`.
    Prints the worst-case remote bandwidth per player and exits 1 when a remote or the total is
    over the budget in src/shared/perf/PerfBudget.luau (ADR 0019). It also checks the load limits
    of `PerfBudget.load` (ADR 0073): instance counts of the place export, the longest session-lock
    wait and the DataStore requests of one join. The logic is in src/shared/perf/RemoteBudget and
    LoadBudget (pure, tested); this file only reads files and reports.
    `schema` defaults to net/schema.zap; `placeCounts` to `PerfBudget.load.placeCountsPath`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local AutoFeel = require("../src/shared/features/autofeel/AutoFeel")
local InMemoryProfileRepository =
    require("../src/shared/features/playerdata/InMemoryProfileRepository")
local InspectView = require("../src/shared/features/inspect/InspectView")
local JoinPolicy = require("../src/shared/features/join/JoinPolicy")
local LoadBudget = require("../src/shared/perf/LoadBudget")
local PerfBudget = require("../src/shared/perf/PerfBudget")
local PlayerData = require("../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerDataService = require("../src/shared/features/playerdata/PlayerDataService")
local PodiumConfig = require("../src/shared/features/podium/PodiumConfig")
local RarityConfig = require("../src/shared/features/rarity/RarityConfig")
local RemoteBudget = require("../src/shared/perf/RemoteBudget")
local TierModelConfig = require("../src/shared/features/tiermodels/TierModelConfig")

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
-- World podium (ADR 0056): the configured refresh must respect the budget floor.
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
-- Tier models (ADR 0057): parts, triangles and distinct silhouettes per tier.
local tierBudget = PerfBudget.tierModels
local tierConfig = Config.default.tierModels
if tierBudget ~= nil and tierConfig ~= nil then
    local problems = TierModelConfig.problems(
        tierConfig,
        Config.default.rarity or RarityConfig.default,
        tierBudget
    )
    for _, problem in problems do
        table.insert(report.failures, problem)
    end
    for _, tier in tierConfig.tiers do
        local parts, triangles = TierModelConfig.cost(tier.recipe)
        print(
            `tier {tier.tierId}: {parts} parts of {tierBudget.maxPartsPerNode}, ~{triangles} triangles of {tierBudget.maxTrianglesPerNode}`
        )
    end
    print(
        `tier models: at most {tierBudget.maxVisibleNodes} nodes in view = {tierBudget.maxVisibleNodes * tierBudget.maxPartsPerNode} parts`
    )
end
-- Auto mining visuals (ADR 0058): popups per second and instances per second for a full lobby.
local autoBudget = PerfBudget.autoFeel
local autoConfig = Config.default.autoFeel
if autoBudget ~= nil and autoConfig ~= nil then
    for _, problem in AutoFeel.validate(autoConfig) do
        table.insert(report.failures, problem)
    end
    local popups = AutoFeel.popupsPerSecond(autoConfig)
    local instances = autoBudget.playersInView
        * AutoFeel.swingsPerSecond(autoConfig)
        * autoBudget.instancesPerSwing
    if popups > autoBudget.maxPopupsPerSecond then
        table.insert(
            report.failures,
            `auto feel popups {popups}/s exceed {autoBudget.maxPopupsPerSecond}/s`
        )
    end
    if instances > autoBudget.maxInstancesPerSecond then
        table.insert(
            report.failures,
            `auto feel instances {instances}/s exceed {autoBudget.maxInstancesPerSecond}/s`
        )
    end
    print(
        `auto feel: {popups} popups/s of {autoBudget.maxPopupsPerSecond}, {instances} instances/s for {autoBudget.playersInView} players of {autoBudget.maxInstancesPerSecond}`
    )
end
-- Item viewer (ADR 0060): the config must be valid and the budget must allow one WorldModel.
local inspectBudget = PerfBudget.inspect
local inspectConfig = Config.default.inspect
if inspectBudget ~= nil and inspectConfig ~= nil then
    for _, problem in InspectView.validate(inspectConfig) do
        table.insert(report.failures, problem)
    end
    for _, problem in InspectView.budgetProblems(inspectBudget.maxParts, 1, inspectBudget) do
        table.insert(report.failures, problem)
    end
    print(
        `inspect: up to {inspectBudget.maxParts} parts, {inspectBudget.maxWorldModels} WorldModel, open under {inspectBudget.maxOpenMs} ms`
    )
end
-- Load limits (ADR 0073): instances of the place export, session-lock wait, DataStore per join.
local loadLimits = PerfBudget.load
if loadLimits ~= nil then
    local placePath = process.args[2] or loadLimits.placeCountsPath
    if fs.isFile(placePath) then
        local decoded: unknown = serde.decode("json", fs.readFile(placePath))
        local read = LoadBudget.readPlaceCounts(decoded)
        if read.ok then
            for _, problem in LoadBudget.instanceProblems(read.value, loadLimits) do
                table.insert(report.failures, problem)
            end
            local capped = 0
            for _ in loadLimits.services do
                capped += 1
            end
            print(`place export {placePath}: checked {capped} capped services`)
        else
            table.insert(report.failures, `place export {placePath}: {read.error}`)
        end
    else
        print(`place export {placePath}: not found, instance caps skipped (generate it per game)`)
    end

    local waited = LoadBudget.simulateSessionWait(function(clock)
        return JoinPolicy.newWait({
            clock = clock,
            isGone = function(): boolean
                return false
            end,
        })
    end, loadLimits.session.pollSeconds, LoadBudget.waitCeilingSeconds(loadLimits))
    for _, problem in LoadBudget.sessionWaitProblems(waited, loadLimits) do
        table.insert(report.failures, problem)
    end
    print(`session wait: {waited} s of {loadLimits.session.maxWaitSeconds} s`)

    local function clonePlayerData(data: PlayerData.PlayerData): PlayerData.PlayerData
        return {
            schemaVersion = data.schemaVersion,
            coins = data.coins,
            purchaseIds = table.clone(data.purchaseIds),
            sessionCount = data.sessionCount,
            redeemedCodes = table.clone(data.redeemedCodes),
            timeRewards = table.clone(data.timeRewards),
            settings = table.clone(data.settings),
            communityRewardClaimed = data.communityRewardClaimed,
        }
    end
    local counter = LoadBudget.newRequestCounter()
    local joinService = PlayerDataService.new({
        repository = LoadBudget.countingRepository(
            InMemoryProfileRepository.new({
                default = PlayerData.default,
                clone = clonePlayerData,
            }),
            counter
        ),
        onSessionLost = function(_key: string) end,
        migrate = PlayerDataMigrations.migrateInPlace,
        startSession = function(data: PlayerData.PlayerData): number
            data.sessionCount += 1
            return data.sessionCount
        end,
    })
    local joined = joinService:join("perf-budget")
    if not joined.ok then
        table.insert(report.failures, `join probe failed: {tostring(joined.error)}`)
    end
    for _, problem in LoadBudget.dataStoreProblems(counter:total(), loadLimits) do
        table.insert(report.failures, problem)
    end
    print(
        `datastore: {counter:total()} requests per join of {loadLimits.dataStore.maxRequestsPerJoin}`
    )
end
if #report.failures > 0 then
    for _, failure in report.failures do
        print(`FAIL {failure}`)
    end
    process.exit(1)
end
print("perf-budget: OK")
