--!strict
local FishRoll = require("../../../src/shared/features/reef/FishRoll")
local ReefConfig = require("../../../src/shared/features/reef/ReefConfig")
local harness = require("../../harness")

local function cloneTable(source: ReefConfig.ReefTable): ReefConfig.ReefTable
    local zones: { ReefConfig.Zone } = {}
    for _, zone in source.zones do
        local fish: { ReefConfig.Fish } = {}
        for _, entry in zone.fish do
            table.insert(fish, table.clone(entry))
        end
        local copy = table.clone(zone)
        copy.fish = fish
        table.insert(zones, copy)
    end
    local rods: { ReefConfig.Rod } = {}
    for _, rod in source.rods do
        table.insert(rods, table.clone(rod))
    end
    return { zones = zones, rods = rods }
end

return function(suite: harness.Harness)
    suite:test("the default table is valid", function()
        harness.equal(#ReefConfig.validate(ReefConfig.default), 0, "problems")
    end)

    suite:test("deeper zones pay more on average", function()
        local previous = 0
        for _, zone in ReefConfig.default.zones do
            local total, weights = 0, 0
            for _, fish in zone.fish do
                total += fish.value * fish.weight
                weights += fish.weight
            end
            harness.isTrue(total / weights > previous, `zone {zone.index} pays more`)
            previous = total / weights
        end
    end)

    suite:test("validate reports each kind of bad value", function()
        local broken = cloneTable(ReefConfig.default)
        broken.zones[1].index = 5
        broken.zones[1].biteMinSeconds = 0
        broken.zones[1].fish[1].weight = 0
        broken.zones[1].fish[2].id = broken.zones[1].fish[1].id
        broken.zones[1].fish[3].value = 1.5
        broken.zones[2].fish = {}
        broken.rods[1].price = 3
        broken.rods[2].level = 9
        broken.rods[3].maxZone = 99
        broken.rods[3].price = -1
        local problems = ReefConfig.validate(broken)
        harness.isTrue(#problems >= 9, `found {#problems} problems`)
    end)

    suite:test("an empty table is invalid", function()
        harness.isTrue(#ReefConfig.validate({ zones = {}, rods = {} }) >= 2, "problems")
    end)

    suite:test("rod and fishValue look up by key and return nil when unknown", function()
        local rod = ReefConfig.rod(ReefConfig.default, 2)
        harness.isTrue(rod ~= nil and rod.maxZone == 2, "rod 2")
        harness.isTrue(ReefConfig.rod(ReefConfig.default, 0) == nil, "rod 0")
        harness.equal(ReefConfig.fishValue(ReefConfig.default, "tuna"), 60, "tuna")
        harness.isTrue(ReefConfig.fishValue(ReefConfig.default, "ghost") == nil, "unknown")
    end)

    suite:test("pickFish walks the weights and clamps its input", function()
        local zone = ReefConfig.default.zones[1]
        harness.equal(FishRoll.pickFish(zone, 0), "minnow", "low")
        harness.equal(FishRoll.pickFish(zone, 0.69), "minnow", "end of minnow")
        harness.equal(FishRoll.pickFish(zone, 0.7), "sardine", "start of sardine")
        harness.equal(FishRoll.pickFish(zone, 0.96), "perch", "rare")
        harness.equal(FishRoll.pickFish(zone, 5), "perch", "clamped high")
        harness.equal(FishRoll.pickFish(zone, -1), "minnow", "clamped low")
    end)

    suite:test("biteDelay stays inside the zone range", function()
        local zone = ReefConfig.default.zones[2]
        harness.equal(FishRoll.biteDelay(zone, 0), zone.biteMinSeconds, "min")
        harness.equal(FishRoll.biteDelay(zone, 1), zone.biteMaxSeconds, "max")
        harness.equal(FishRoll.biteDelay(zone, 7), zone.biteMaxSeconds, "clamped")
    end)
end
