--!strict
local InMemoryProfileRepository =
    require("../../../src/shared/features/playerdata/InMemoryProfileRepository")
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataService = require("../../../src/shared/features/playerdata/PlayerDataService")
local harness = require("../../harness")

local function clone(data: PlayerData.PlayerData): PlayerData.PlayerData
    return {
        schemaVersion = data.schemaVersion,
        coins = data.coins,
        purchases = table.clone(data.purchases),
    }
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
            joined.value.coins = 7
        end
        harness.isTrue(service:leave("1").ok, "leave ok")
        harness.isTrue(service:get("1") == nil, "data dropped after leave")
        local rejoined = service:join("1")
        harness.isTrue(rejoined.ok and rejoined.value.coins == 7, "coins persisted")
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
end
