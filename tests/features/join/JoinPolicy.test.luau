--!strict
local InMemoryProfileRepository =
    require("../../../src/shared/features/playerdata/InMemoryProfileRepository")
local JoinPolicy = require("../../../src/shared/features/playerdata/JoinPolicy")
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerDataService = require("../../../src/shared/features/playerdata/PlayerDataService")
local harness = require("../../harness")

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
        mining = table.clone(data.mining),
    }
end

local function newService()
    local repository = InMemoryProfileRepository.new({
        default = PlayerData.default,
        clone = clone,
    })
    local service = PlayerDataService.new({
        repository = repository,
        onSessionLost = function(_key: string) end,
        migrate = PlayerDataMigrations.migrateInPlace,
        startSession = function(data: PlayerData.PlayerData): number
            data.sessionCount += 1
            return data.sessionCount
        end,
    })
    return service
end

return function(suite: harness.Harness)
    suite:test("the wait says stop when the player has left", function()
        local gone = false
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return 0
            end,
            isGone = function(): boolean
                return gone
            end,
        })
        harness.isFalse(wait.cancel(), "still here")
        gone = true
        harness.isTrue(wait.cancel(), "left")
        harness.isFalse(wait.timedOut(), "leaving is not a timeout")
    end)

    suite:test("our own policy cancels the wait at 90 s", function()
        local now = 1000
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return now
            end,
            isGone = function(): boolean
                return false
            end,
        })
        now = 1000 + JoinPolicy.MAX_WAIT_SECONDS - 0.5
        harness.isFalse(wait.cancel(), "just under the limit")
        harness.isFalse(wait.timedOut(), "not timed out yet")
        now = 1000 + JoinPolicy.MAX_WAIT_SECONDS
        harness.isTrue(wait.cancel(), "at the limit")
        harness.isTrue(wait.timedOut(), "timed out")
        harness.equal(JoinPolicy.MAX_WAIT_SECONDS, 90, "the policy is 90 s")
    end)

    suite:test("timedOut is read from the injected clock, not from a retry count", function()
        local now = 0
        local gone = false
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return now
            end,
            isGone = function(): boolean
                return gone
            end,
            maxWaitSeconds = 10,
        })
        harness.isFalse(wait.timedOut(), "fresh")
        now = 9.9
        harness.isFalse(wait.timedOut(), "under the limit, however many times cancel was polled")
        for _ = 1, 50 do
            wait.cancel()
        end
        harness.isFalse(wait.timedOut(), "polling does not change it")
        now = 10
        harness.isTrue(wait.timedOut(), "limit reached by the clock")
        gone = true
        harness.isFalse(wait.timedOut(), "a player who left did not time out")
    end)

    suite:test("session_unavailable has its own distinct message", function()
        local unavailable = JoinPolicy.kickMessage(false, "session_unavailable")
        harness.equal(unavailable, JoinPolicy.KICK_UNAVAILABLE, "own message")
        harness.isTrue(unavailable ~= JoinPolicy.KICK_FAILED, "not the generic one")
        harness.isTrue(unavailable ~= JoinPolicy.KICK_TIMED_OUT, "not the timeout one")
        harness.equal(
            JoinPolicy.kickMessage(true, "session_unavailable"),
            JoinPolicy.KICK_TIMED_OUT,
            "timeout wins"
        )
        harness.equal(
            JoinPolicy.kickMessage(false, "save_failed"),
            JoinPolicy.KICK_FAILED,
            "others"
        )
    end)

    suite:test("the kick message says what happened", function()
        harness.equal(JoinPolicy.kickMessage(true), JoinPolicy.KICK_TIMED_OUT, "timeout")
        harness.equal(JoinPolicy.kickMessage(false), JoinPolicy.KICK_FAILED, "failure")
        harness.isTrue(JoinPolicy.KICK_TIMED_OUT ~= JoinPolicy.KICK_FAILED, "distinct")
    end)

    suite:test("a join cancelled by the callback fails without taking the session", function()
        local service = newService()
        local joined = service:join("1", {
            cancel = function(): boolean
                return true
            end,
        })
        harness.isFalse(joined.ok, "cancelled")
        harness.isTrue(service:get("1") == nil, "no profile held")
        harness.isTrue(service:join("1").ok, "the key is free for a later join")
    end)

    suite:test("the service hands the cancel callback to the repository", function()
        local seen = 0
        local repository = InMemoryProfileRepository.new({
            default = PlayerData.default,
            clone = clone,
        })
        local wrapped = {
            load = function(_self: unknown, key: string, options: PlayerDataService.LoadOptions?)
                if options ~= nil and options.cancel ~= nil then
                    seen += 1
                end
                return repository:load(key, options)
            end,
        }
        local service = PlayerDataService.new({
            repository = wrapped,
            onSessionLost = function(_key: string) end,
            migrate = PlayerDataMigrations.migrateInPlace,
            startSession = function(data: PlayerData.PlayerData): number
                return data.sessionCount
            end,
        })
        service:join("5", {
            cancel = function(): boolean
                return false
            end,
        })
        harness.equal(seen, 1, "cancel reached the repository")
    end)

    suite:test("guard returns true and calls nothing when the join works", function()
        local failures = 0
        local ok = JoinPolicy.guard(function() end, function(_message: string)
            failures += 1
        end)
        harness.isTrue(ok, "ok")
        harness.equal(failures, 0, "no failure callback")
    end)

    suite:test("guard never throws: an error becomes a failure callback", function()
        local captured = ""
        local ok = JoinPolicy.guard(function()
            error("boom")
        end, function(message: string)
            captured = message
        end)
        harness.isFalse(ok, "reported as failed")
        harness.isTrue(string.find(captured, "boom", 1, true) ~= nil, "message kept")
    end)

    suite:test("guard survives a failure callback that throws too", function()
        local reported = ""
        local ok = JoinPolicy.guard(function()
            error("first")
        end, function(_message: string)
            error("second")
        end, function(message: string)
            reported = message
        end)
        harness.isFalse(ok, "reported as failed, not thrown")
        harness.isTrue(string.find(reported, "second", 1, true) ~= nil, "handler error surfaced")
        harness.isTrue(string.find(reported, "first", 1, true) ~= nil, "original kept")
    end)
end
