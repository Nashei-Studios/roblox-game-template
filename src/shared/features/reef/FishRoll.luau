--!strict
--[[
    Pure catch roll (ADR 0021). The RNG is injected (returns a number in [0, 1)), so tests
    control luck. The roll never sees bait: bait only shortens the delay, so nothing paid
    changes what a player can catch.
]]

local ReefConfig = require("./ReefConfig")

local FishRoll = {}

--- Picks a fish id from `zone` by weight. `roll` is in [0, 1).
function FishRoll.pickFish(zone: ReefConfig.Zone, roll: number): string
    local total = 0
    for _, fish in zone.fish do
        total += fish.weight
    end
    local target = math.clamp(roll, 0, 0.999999999) * total
    local running = 0
    for _, fish in zone.fish do
        running += fish.weight
        if target < running then
            return fish.id
        end
    end
    return zone.fish[#zone.fish].id
end

--- Bite delay in seconds inside the zone range. `roll` is in [0, 1).
function FishRoll.biteDelay(zone: ReefConfig.Zone, roll: number): number
    local span = zone.biteMaxSeconds - zone.biteMinSeconds
    return zone.biteMinSeconds + math.clamp(roll, 0, 1) * span
end

return FishRoll
