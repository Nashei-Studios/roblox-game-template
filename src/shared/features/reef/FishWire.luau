--!strict
--[[
    Maps a fish id from ReefConfig to the Zap enum that crosses the wire. The map is typed
    against the generated `FishName`, so the analyzer rejects a name the schema does not have;
    its test rejects a fish in ReefConfig that the map does not have.
]]

local Types = require("../../net/generated/types")

local FishWire = {}

FishWire.names = {
    minnow = "minnow",
    sardine = "sardine",
    perch = "perch",
    mackerel = "mackerel",
    snapper = "snapper",
    grouper = "grouper",
    tuna = "tuna",
    swordfish = "swordfish",
    marlin = "marlin",
} :: { [string]: Types.FishName }

--- The wire name of `fishId`, or nil when the schema does not know it.
function FishWire.toWire(fishId: string): Types.FishName?
    return FishWire.names[fishId]
end

return FishWire
