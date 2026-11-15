--!strict
local InMemoryProfileRepository =
    require("../../src/shared/features/playerdata/InMemoryProfileRepository")
local JoinPolicy = require("../../src/shared/features/join/JoinPolicy")
local LoadBudget = require("../../src/shared/perf/LoadBudget")
local PerfBudget = require("../../src/shared/perf/PerfBudget")
local PlayerData = require("../../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerDataService = require("../../src/shared/features/playerdata/PlayerDataService")
local harness = require("../harness")

local function limits(): LoadBudget.Limits
    return {
        placeCountsPath = "perf/place-counts.json",
        services = {
            Workspace = { maxInstances = 100, maxParts = 60 },
            StarterGui = { maxInstances = 10 },
        },
        session = { maxWaitSeconds = 90, pollSeconds = 5 },
        dataStore = { maxRequestsPerJoin = 3 },
    }
end

local function clone(data: PlayerData.PlayerData): PlayerData.PlayerData
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

local function startSession(data: PlayerData.PlayerData): number
    data.sessionCount += 1
    return data.sessionCount
end

local function newMemory()
    return InMemoryProfileRepository.new({ default = PlayerData.default, clone = clone })
end

local function stillHere(): boolean
    return false
end

local function countedJoin(extraRequests: number): number
    local counter = LoadBudget.newRequestCounter()
    local service = PlayerDataService.new({
        repository = LoadBudget.countingRepository(newMemory(), counter),
        onSessionLost = function(_key: string) end,
        migrate = PlayerDataMigrations.migrateInPlace,
        startSession = startSession,
    })
    local joined = service:join("1")
    harness.isTrue(joined.ok, "join ok")
    for _ = 1, extraRequests do
        counter:record()
    end
    return counter:total()
end

return function(suite: harness.Harness)
    suite:test("readPlaceCounts accepts a well-formed export", function()
        local read = LoadBudget.readPlaceCounts({
            services = {
                Workspace = { instances = 12, parts = 7 },
                StarterGui = { instances = 3 },
            },
        })
        harness.isTrue(read.ok, "read ok")
        if read.ok then
            harness.equal(read.value.Workspace.instances, 12)
            harness.equal(read.value.Workspace.parts, 7)
            harness.equal(read.value.StarterGui.parts, nil)
        end
    end)

    suite:test("readPlaceCounts rejects malformed exports with a reason", function()
        local bad: { unknown } = {
            "text",
            {},
            { services = { Workspace = 5 } },
            { services = { Workspace = { instances = -1 } } },
            { services = { Workspace = { instances = "9" } } },
            { services = { Workspace = { instances = 1, parts = "x" } } },
            { services = { [1] = { instances = 1 } } },
        }
        for index, value in bad do
            harness.isFalse(LoadBudget.readPlaceCounts(value).ok, `case {index}`)
        end
    end)

    suite:test("instances under every cap give no problems", function()
        local problems = LoadBudget.instanceProblems({
            Workspace = { instances = 100, parts = 60 },
            StarterGui = { instances = 10 },
            Lighting = { instances = 99999 },
        }, limits())
        harness.equal(#problems, 0)
    end)

    suite:test("instances over a cap are reported per service, sorted", function()
        local problems = LoadBudget.instanceProblems({
            Workspace = { instances = 101, parts = 61 },
            StarterGui = { instances = 11 },
        }, limits())
        harness.equal(#problems, 3)
        harness.equal(problems[1], "StarterGui has 11 instances, cap 10")
        harness.equal(problems[2], "Workspace has 101 instances, cap 100")
        harness.equal(problems[3], "Workspace has 61 parts, cap 60")
    end)

    suite:test("a capped service missing from the export is a problem, not a pass", function()
        local problems = LoadBudget.instanceProblems({ Workspace = { instances = 1 } }, limits())
        harness.equal(#problems, 2)
        harness.equal(problems[1], "place export has no entry for StarterGui")
        harness.equal(problems[2], "place export has no part count for Workspace")
    end)

    suite:test("a wait that honours the policy ends within the cap", function()
        local waited = LoadBudget.simulateSessionWait(function(clock)
            return JoinPolicy.newWait({ clock = clock, isGone = stillHere })
        end, 5, LoadBudget.waitCeilingSeconds(limits()))
        harness.equal(waited, 90)
        harness.equal(#LoadBudget.sessionWaitProblems(waited, limits()), 0)
    end)

    suite:test("a wait longer than the cap fails the gate", function()
        local waited = LoadBudget.simulateSessionWait(function(clock)
            return JoinPolicy.newWait({
                clock = clock,
                isGone = stillHere,
                maxWaitSeconds = 120,
            })
        end, 5, LoadBudget.waitCeilingSeconds(limits()))
        harness.equal(waited, 120)
        local problems = LoadBudget.sessionWaitProblems(waited, limits())
        harness.equal(#problems, 1)
        harness.equal(problems[1], "session-lock wait 120 s, cap 90 s")
    end)

    suite:test("a wait with no limit is reported as unbounded instead of hanging", function()
        local waited = LoadBudget.simulateSessionWait(function(_clock)
            return {
                cancel = function(): boolean
                    return false
                end,
            }
        end, 5, LoadBudget.waitCeilingSeconds(limits()))
        harness.equal(waited, math.huge)
        harness.equal(
            LoadBudget.sessionWaitProblems(waited, limits())[1],
            "session-lock wait never ends, cap 90 s"
        )
    end)

    suite:test("a join through the real service stays within the DataStore cap", function()
        local requests = countedJoin(0)
        harness.equal(requests, 1)
        harness.equal(#LoadBudget.dataStoreProblems(requests, limits()), 0)
    end)

    suite:test("a join that issues requests over the cap fails the gate", function()
        local requests = countedJoin(3)
        harness.equal(requests, 4)
        local problems = LoadBudget.dataStoreProblems(requests, limits())
        harness.equal(problems[1], "join issues 4 DataStore requests, cap 3")
    end)

    suite:test("load, save and release count as requests and a locked load counts too", function()
        local counter = LoadBudget.newRequestCounter()
        local repository = LoadBudget.countingRepository(newMemory(), counter)
        local loaded = repository:load("1")
        harness.isTrue(loaded.ok, "load ok")
        if loaded.ok then
            harness.isTrue(loaded.value:isActive(), "active")
            loaded.value:onSessionEnd(function() end)
            harness.isTrue(loaded.value:save().ok, "save ok")
            local confirmed = loaded.value:confirmSaved(function(_saved): boolean
                return true
            end, 1)
            harness.isTrue(confirmed.ok, "confirm ok")
            harness.isTrue(loaded.value:release().ok, "release ok")
        end
        harness.equal(counter:total(), 3)
        local again = repository:load("1")
        local locked = repository:load("1")
        harness.isTrue(again.ok, "relock after release")
        harness.isFalse(locked.ok, "locked key fails")
        harness.equal(counter:total(), 5)
    end)

    suite:test("the shipped limits cover the shipped join policy", function()
        local shipped = PerfBudget.load
        harness.isTrue(shipped ~= nil, "PerfBudget.load exists")
        if shipped ~= nil then
            harness.isTrue(
                shipped.session.maxWaitSeconds >= JoinPolicy.MAX_WAIT_SECONDS,
                "cap covers the policy limit"
            )
            harness.isTrue(shipped.session.pollSeconds > 0, "poll interval is positive")
        end
    end)
end
