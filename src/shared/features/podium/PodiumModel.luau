--!strict
--[[
    The podium as data: from the top entries and the filtered names to three places with their
    plate text and medal colors. Pure. The medal colors come from RarityFx (ADR 0048), so place 1
    looks like a Legendary card and the plate matches the rest of the game. An empty pedestal
    gets the neutral locked look (RarityFx.lockedSpec) and the "Be the first" line.
]]

local PodiumConfig = require("./PodiumConfig")
local PodiumFormat = require("./PodiumFormat")
local PodiumSource = require("../../ports/PodiumSource")
local RarityConfig = require("../rarity/RarityConfig")
local RarityFx = require("../rarity/RarityFx")

export type Entry = PodiumSource.Entry

export type Place = {
    rank: number,
    occupied: boolean,
    -- nil on an empty pedestal.
    userId: number?,
    -- Plate line 1: the filtered name, or the empty label.
    headline: string,
    -- Plate line 2: the formatted value, "" on an empty pedestal.
    detail: string,
    -- Medal tier label ("Legendary"); "" on an empty pedestal (rarity is never color alone).
    tierLabel: string,
    frameHex: string,
    backgroundTopHex: string,
    backgroundBottomHex: string,
    glow: boolean,
}

export type View = {
    places: { Place },
    occupiedCount: number,
    -- Changes only when something a player can see changes (who stands where, name, value).
    signature: string,
}

local PodiumModel = {}

--- Cuts `name` to `maxLength` characters, ending in "..." when it was cut.
function PodiumModel.cutName(name: string, maxLength: number): string
    if #name <= maxLength then
        return name
    end
    return `{string.sub(name, 1, maxLength - 3)}...`
end

--- Builds the three places. `entries` are best first; extra entries are ignored. `nameOf` must
--- never fail: it returns the filtered name or the config's unknown name.
function PodiumModel.build(
    config: PodiumConfig.PodiumConfig,
    rarity: RarityConfig.Config,
    surfaceHex: string,
    entries: { Entry },
    nameOf: (userId: number) -> string
): View
    local places: { Place } = {}
    local occupiedCount = 0
    local parts: { string } = {}
    for rank = 1, PodiumConfig.PLACES do
        local entry = entries[rank]
        if entry ~= nil then
            local tierId = config.placeTierIds[rank]
            local spec = RarityFx.spec(rarity, tierId, "high", surfaceHex)
            local headline = PodiumModel.cutName(nameOf(entry.userId), config.nameMaxLength)
            local detail = PodiumFormat.value(entry.value, config.valueUnit)
            occupiedCount += 1
            table.insert(places, {
                rank = rank,
                occupied = true,
                userId = entry.userId,
                headline = headline,
                detail = detail,
                tierLabel = spec.label,
                frameHex = spec.frameHex,
                backgroundTopHex = spec.backgroundTopHex,
                backgroundBottomHex = spec.backgroundBottomHex,
                glow = spec.glow,
            })
            table.insert(parts, `{entry.userId}:{headline}:{detail}`)
        else
            local locked = RarityFx.lockedSpec(rarity, surfaceHex)
            table.insert(places, {
                rank = rank,
                occupied = false,
                userId = nil,
                headline = config.emptyLabel,
                detail = "",
                tierLabel = "",
                frameHex = locked.frameHex,
                backgroundTopHex = locked.backgroundTopHex,
                backgroundBottomHex = locked.backgroundBottomHex,
                glow = false,
            })
            table.insert(parts, "-")
        end
    end
    return {
        places = places,
        occupiedCount = occupiedCount,
        signature = table.concat(parts, "|"),
    }
end

--- The view with three empty pedestals: the fallback when no data has been read yet or reading
--- failed with nothing cached.
function PodiumModel.empty(
    config: PodiumConfig.PodiumConfig,
    rarity: RarityConfig.Config,
    surfaceHex: string
): View
    return PodiumModel.build(config, rarity, surfaceHex, {}, function(): string
        return config.unknownName
    end)
end

return PodiumModel
