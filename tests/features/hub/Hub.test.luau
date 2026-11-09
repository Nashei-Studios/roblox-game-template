--!strict
local HubEmotes = require("../../../src/shared/features/hub/HubEmotes")
local HubLayout = require("../../../src/shared/features/hub/HubLayout")
local HubRegistry = require("../../../src/shared/features/hub/HubRegistry")
local harness = require("../../harness")

local function config(): HubLayout.HubConfig
    return {
        id = "main",
        spawn = { radius = 10, minSpacing = 5, ringGap = 8, rings = 2 },
        stations = {
            { id = "shop", kind = "shop", angleDegrees = 0, radius = 40, menuId = "shop" },
            { id = "door", kind = "entrance", angleDegrees = 180, radius = 40 },
        },
        serverCap = 12,
        nameTags = { enabled = true, maxDistance = 60 },
        emotes = { allowed = { "wave", "cheer" }, cooldownSeconds = 2 },
    }
end

local function has(problems: { string }, needle: string): boolean
    return string.find(table.concat(problems, "|"), needle, 1, true) ~= nil
end

return function(suite: harness.Harness)
    suite:test("a valid hub has no problems and no advice", function()
        harness.equal(#HubLayout.validate(config()), 0)
        harness.equal(#HubLayout.advise(config()), 0)
    end)

    suite:test("ring capacity grows with the radius and the plaza adds the rings up", function()
        local spawn = config().spawn
        harness.equal(HubLayout.ringCapacity(spawn, 1), 12)
        harness.equal(HubLayout.ringCapacity(spawn, 2), 22)
        harness.equal(HubLayout.capacity(spawn), 34)
    end)

    suite:test("slot 1 faces the center; past the capacity or a bad index is nil", function()
        local spawn = config().spawn
        local first = HubLayout.spawnPoint(spawn, 1)
        harness.isTrue(first ~= nil)
        if first ~= nil then
            harness.equal(first.ring, 1)
            harness.isTrue(math.abs(first.position.z - 10) < 1e-6, "angle 0 is +Z")
            harness.isTrue(math.abs(first.facing.z + 1) < 1e-6, "looks at the middle")
        end
        local outer = HubLayout.spawnPoint(spawn, 13)
        harness.equal(if outer ~= nil then outer.ring else 0, 2)
        harness.equal(HubLayout.spawnPoint(spawn, 35), nil)
        harness.equal(HubLayout.spawnPoint(spawn, 0), nil)
        harness.equal(HubLayout.spawnPoint(spawn, 1.5), nil)
    end)

    suite:test("no two slots of the plaza share a position", function()
        local spawn = config().spawn
        local seen: { [string]: boolean } = {}
        for slot = 1, HubLayout.capacity(spawn) do
            local point = HubLayout.spawnPoint(spawn, slot)
            harness.isTrue(point ~= nil)
            if point ~= nil then
                local key = string.format("%.3f,%.3f", point.position.x, point.position.z)
                harness.isFalse(seen[key] == true, `slot {slot} repeats {key}`)
                seen[key] = true
            end
        end
    end)

    suite:test("a station angle maps to a position", function()
        local at = HubLayout.stationPosition(config().stations[2])
        harness.isTrue(math.abs(at.z + 40) < 1e-6 and math.abs(at.x) < 1e-6)
    end)

    suite:test("validate reports a station inside the plaza, a duplicate and no kind", function()
        local bad = config()
        bad.stations = {
            { id = "a", kind = "shop", angleDegrees = 0, radius = 5 },
            { id = "a", kind = "", angleDegrees = 0, radius = 40 },
        }
        local problems = HubLayout.validate(bad)
        harness.isTrue(has(problems, "outside the spawn plaza"))
        harness.isTrue(has(problems, "declared twice"))
        harness.isTrue(has(problems, "needs a kind"))
    end)

    suite:test("validate reports a bad cap and a repeated emote", function()
        local bad = config()
        bad.serverCap = 200
        bad.emotes.allowed = { "wave", "wave" }
        local problems = HubLayout.validate(bad)
        harness.isTrue(has(problems, "serverCap must be"))
        harness.isTrue(has(problems, "emote"))
    end)

    suite:test("validate refuses a plaza smaller than the cap and bad numbers", function()
        local small = config()
        small.spawn = { radius = 6, minSpacing = 5, ringGap = 8, rings = 1 }
        harness.isTrue(has(HubLayout.validate(small), "plaza holds"))
        local bad = config()
        bad.spawn = { radius = 0, minSpacing = 0, ringGap = 0, rings = 0.5 }
        bad.id = ""
        bad.nameTags.maxDistance = -1
        bad.emotes.cooldownSeconds = -1
        harness.isTrue(#HubLayout.validate(bad) >= 6)
    end)

    suite:test("advise flags a crowd and a solo hub", function()
        local crowd = config()
        crowd.serverCap = 40
        harness.equal(#HubLayout.advise(crowd), 1)
        local solo = config()
        solo.serverCap = 1
        solo.stations = {}
        harness.equal(#HubLayout.advise(solo), 2)
    end)

    suite:test("the registry seats players in join order and reuses freed slots", function()
        local log: { string } = {}
        local registry = HubRegistry.new({
            config = config(),
            hooks = {
                onArrive = function(id, slot)
                    table.insert(log, `+{id}@{slot}`)
                end,
                onDepart = function(id, slot)
                    table.insert(log, `-{id}@{slot}`)
                end,
            },
        })
        harness.isTrue(registry:join(10) ~= nil)
        harness.isTrue(registry:join(20) ~= nil)
        harness.isTrue(registry:join(30) ~= nil)
        registry:leave(20)
        harness.isTrue(registry:join(40) ~= nil)
        harness.equal(registry:slotOf(40), 2, "takes the freed slot")
        harness.equal(table.concat(registry:seated(), ","), "10,40,30")
        harness.equal(table.concat(log, " "), "+10@1 +20@2 +30@3 -20@2 +40@2")
        harness.equal(registry:occupancy(), 3)
    end)

    suite:test("joining twice keeps the slot; leaving an unknown player is harmless", function()
        local registry = HubRegistry.new({ config = config() })
        harness.isTrue(registry:join(1) ~= nil)
        harness.isTrue(registry:join(1) ~= nil)
        harness.equal(registry:occupancy(), 1)
        registry:leave(999)
        harness.equal(registry:spawnFor(999), nil)
        harness.equal(registry:slotOf(999), nil)
        harness.isTrue(registry:spawnFor(1) ~= nil)
    end)

    suite:test("a player over the cap is not placed", function()
        local small = config()
        small.serverCap = 2
        local registry = HubRegistry.new({ config = small })
        harness.isTrue(registry:join(1) ~= nil)
        harness.isTrue(registry:join(2) ~= nil)
        harness.isTrue(registry:isFull())
        harness.equal(registry:join(3), nil)
        registry:leave(1)
        harness.isFalse(registry:isFull())
        harness.isTrue(registry:join(3) ~= nil)
    end)

    suite:test("emotes: unknown id, cooldown, then accepted again", function()
        local clock = { now = 100 }
        local emotes = HubEmotes.new({
            policy = config().emotes,
            now = function()
                return clock.now
            end,
        })
        harness.equal(emotes:request(1, "dance").reason, "unknown_emote")
        harness.isTrue(emotes:request(1, "wave").accepted)
        harness.equal(emotes:request(1, "cheer").reason, "cooldown")
        harness.isTrue(emotes:request(2, "cheer").accepted, "another player is independent")
        clock.now = 102
        harness.isTrue(emotes:request(1, "cheer").accepted)
        emotes:forget(1)
        harness.isTrue(emotes:request(1, "wave").accepted, "forgotten players start clean")
    end)
end
