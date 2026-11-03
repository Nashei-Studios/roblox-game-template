--!strict
local InMemoryProfileRepository =
    require("../../../src/shared/features/playerdata/InMemoryProfileRepository")
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataService = require("../../../src/shared/features/playerdata/PlayerDataService")
local harness = require("../../harness")

local function clone(data: PlayerData.PlayerData): PlayerData.PlayerData
    return {
        schemaVersion = data.schemaVersion,
        coins = data.coins,
        purchaseIds = table.clone(data.purchaseIds),
        sessionCount = data.sessionCount,
        rodLevel = data.rodLevel,
        bait = data.bait,
        totalCatches = data.totalCatches,
        fishStock = table.clone(data.fishStock),
    }
end

local function startSession(data: PlayerData.PlayerData): number
    data.sessionCount += 1
    return data.sessionCount
end

local function newService(lost: { string })
    local repository = InMemoryProfileRepository.new({
        default = PlayerData.default,
        clone = clone,
    })
    local service = PlayerDataService.new({
        repository = repository,
        onSessionLost = function(key: string)
            table.insert(lost, key)
        end,
        migrate = PlayerDataMigrations.migrateInPlace,
        startSession = startSession,
    })
    return service, repository
end

return function(suite: harness.Harness)
    suite:test("join loads default data and get returns it", function()
        local service = newService({})
        local joined = service:join("1")
        harness.isTrue(joined.ok, "join ok")
        local data = service:get("1")
        harness.isTrue(data ~= nil and data.coins == 0, "default data")
    end)

    suite:test("get is nil for a player that never joined", function()
        local service = newService({})
        harness.isTrue(service:get("9") == nil, "no data")
    end)

    suite:test("joining twice is refused", function()
        local service = newService({})
        service:join("1")
        harness.isFalse(service:join("1").ok, "second join")
    end)

    suite:test("leave persists changes and a rejoin sees them", function()
        local service = newService({})
        local joined = service:join("1")
        if joined.ok then
            joined.value.data.coins = 7
        end
        harness.isTrue(service:leave("1").ok, "leave ok")
        harness.isTrue(service:get("1") == nil, "data dropped after leave")
        local rejoined = service:join("1")
        harness.isTrue(rejoined.ok and rejoined.value.data.coins == 7, "coins persisted")
    end)

    suite:test("leave without join reports not_active", function()
        local service = newService({})
        local left = service:leave("1")
        harness.isFalse(left.ok, "leave must fail")
    end)

    suite:test("a session ended elsewhere is reported once and the data is dropped", function()
        local lost: { string } = {}
        local inner = InMemoryProfileRepository.new({ default = PlayerData.default, clone = clone })
        local captured: InMemoryProfileRepository.ProfileHandle<PlayerData.PlayerData>? = nil
        local service = PlayerDataService.new({
            repository = {
                load = function(_self, key: string)
                    local loaded = inner:load(key)
                    if loaded.ok then
                        captured = loaded.value
                    end
                    return loaded
                end,
            },
            onSessionLost = function(key: string)
                table.insert(lost, key)
            end,
            migrate = PlayerDataMigrations.migrateInPlace,
            startSession = startSession,
        })
        service:join("1")
        harness.isTrue(captured ~= nil, "handle captured")
        -- Releasing the handle behind the service's back stands in for another server taking over.
        if captured ~= nil then
            captured:release()
        end
        harness.equal(#lost, 1, "lost callbacks")
        harness.isTrue(service:get("1") == nil, "data dropped")
    end)

    suite:test("join returns a 1-based sessionIndex that grows across sessions", function()
        local service = newService({})
        local first = service:join("1")
        harness.isTrue(first.ok and first.value.sessionIndex == 1, "first session")
        service:leave("1")
        local second = service:join("1")
        harness.isTrue(second.ok and second.value.sessionIndex == 2, "second session")
        local data = service:get("1")
        harness.isTrue(data ~= nil and data.sessionCount == 2, "persisted count")
    end)

    suite:test("a failed migration fails the join, frees the lock and exposes no data", function()
        local repository = InMemoryProfileRepository.new({
            default = function(): PlayerData.PlayerData
                local data = PlayerData.default()
                data.schemaVersion = 99 -- written by a newer server
                return data
            end,
            clone = clone,
        })
        local service = PlayerDataService.new({
            repository = repository,
            onSessionLost = function() end,
            migrate = PlayerDataMigrations.migrateInPlace,
            startSession = startSession,
        })
        local joined = service:join("1")
        harness.isFalse(joined.ok, "join must fail")
        if not joined.ok then
            local failure: unknown = joined.error
            harness.isTrue(
                type(failure) == "table" and (failure :: { kind: string }).kind == "future_version",
                "typed error"
            )
        end
        harness.isTrue(service:get("1") == nil, "no data exposed")
        harness.isTrue(repository:load("1").ok, "lock was released")
    end)

    suite:test("legacy v1 data is migrated before it is exposed", function()
        local repository = InMemoryProfileRepository.new({
            default = function(): PlayerData.PlayerData
                -- A profile saved by schema v1, stored under the current type for the fake.
                local legacy: unknown = { schemaVersion = 1, coins = 40, purchases = {} }
                return legacy :: PlayerData.PlayerData
            end,
            -- Identity clone: the legacy table has no current-schema fields to copy.
            clone = function(data: PlayerData.PlayerData): PlayerData.PlayerData
                return data
            end,
        })
        local service = PlayerDataService.new({
            repository = repository,
            onSessionLost = function() end,
            migrate = PlayerDataMigrations.migrateInPlace,
            startSession = startSession,
        })
        local joined = service:join("1")
        harness.isTrue(joined.ok, "join ok")
        if joined.ok then
            harness.equal(joined.value.data.schemaVersion, 4, "schemaVersion")
            harness.equal(joined.value.data.coins, 40, "coins kept")
            harness.equal(joined.value.sessionIndex, 1, "sessionIndex")
        end
    end)

    suite:test(
        "confirmSaved delegates to the player's handle and reports not_active when absent",
        function()
            local service = newService({})
            local missing = service:confirmSaved("9", function(): boolean
                return true
            end, 1)
            harness.isFalse(missing.ok, "no data loaded")
            service:join("1")
            local present = service:confirmSaved(
                "1",
                function(saved: PlayerData.PlayerData): boolean
                    return saved.sessionCount == 1
                end,
                1
            )
            harness.isTrue(present.ok, "confirmed")
        end
    )
end
