--!strict
--[[
    Hub layout contract: where players appear and where the stations of a central hub live, as
    data. Pure: loads under Lune. A hub is the one place where every menu and entrance is
    reachable and where players SEE each other (win-condition checklist, criterion 3).

    Geometry (XZ plane, the hub origin is the center, studs):
    - angle 0 points to +Z and grows clockwise seen from above: position = (sin a * r, cos a * r).
    - The spawn plaza is `spawn.rings` concentric rings; a player gets the lowest free slot.
    - Stations sit OUTSIDE the plaza, so no avatar spawns on top of a shop or an entrance.
    The module never names a game: station kinds and ids are strings the game picks.
]]

export type Vec2 = { x: number, z: number }

export type SpawnRing = {
    -- Radius of the innermost ring, studs.
    radius: number,
    -- Minimum arc distance between two avatars on the same ring, studs.
    minSpacing: number,
    -- Distance between two rings, studs.
    ringGap: number,
    -- How many concentric rings exist (at least 1).
    rings: number,
}

export type Station = {
    -- Stable id, 1 to 32 characters.
    id: string,
    -- Free-form kind the game maps to a prompt or a menu (shop, entrance, objective).
    kind: string,
    angleDegrees: number,
    radius: number,
    -- Optional menu the station opens (an id of the game UI, resolved by the game).
    menuId: string?,
}

export type NameTags = { enabled: boolean, maxDistance: number }

export type EmotePolicy = {
    -- Emote ids the hub accepts (the game maps each to an animation).
    allowed: { string },
    cooldownSeconds: number,
}

export type HubConfig = {
    id: string,
    spawn: SpawnRing,
    stations: { Station },
    -- Players per server this hub is built for.
    serverCap: number,
    nameTags: NameTags,
    emotes: EmotePolicy,
}

export type SpawnPoint = {
    ring: number,
    position: Vec2,
    -- Unit vector from the slot to the hub center (the avatar looks at the middle).
    facing: Vec2,
}

-- Median server size of the 51 games under 90 days with 10k+ CCU in the Up-and-Coming sort
-- (vault research/2026-11-08-win-condition.md section 2: one day, one sort, no causality).
local MEDIAN_SERVER_SIZE = 12
local MAX_SERVER_CAP = 100

local HubLayout = {}

HubLayout.MEDIAN_SERVER_SIZE = MEDIAN_SERVER_SIZE

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- How many avatars fit on ring number `ringIndex` (1 = innermost).
function HubLayout.ringCapacity(spawn: SpawnRing, ringIndex: number): number
    local radius = spawn.radius + (ringIndex - 1) * spawn.ringGap
    return math.max(1, math.floor(2 * math.pi * radius / spawn.minSpacing))
end

--- Total avatar slots of the plaza.
function HubLayout.capacity(spawn: SpawnRing): number
    local total = 0
    for ring = 1, spawn.rings do
        total += HubLayout.ringCapacity(spawn, ring)
    end
    return total
end

local function position(angleDegrees: number, radius: number): Vec2
    local angle = math.rad(angleDegrees)
    return { x = math.sin(angle) * radius, z = math.cos(angle) * radius }
end

--- The spawn point of slot `slotIndex` (1-based, filling ring 1 first). nil past the capacity.
function HubLayout.spawnPoint(spawn: SpawnRing, slotIndex: number): SpawnPoint?
    if slotIndex < 1 or slotIndex % 1 ~= 0 then
        return nil
    end
    local remaining = slotIndex
    for ring = 1, spawn.rings do
        local count = HubLayout.ringCapacity(spawn, ring)
        if remaining <= count then
            local radius = spawn.radius + (ring - 1) * spawn.ringGap
            -- Even rings are offset by half a step so the rings do not line up in spokes.
            local offset = if ring % 2 == 0 then 180 / count else 0
            local at = position((remaining - 1) * 360 / count + offset, radius)
            return {
                ring = ring,
                position = at,
                facing = { x = -at.x / radius, z = -at.z / radius },
            }
        end
        remaining -= count
    end
    return nil
end

--- Where a station stands.
function HubLayout.stationPosition(station: Station): Vec2
    return position(station.angleDegrees, station.radius)
end

local function validateSpawn(config: HubConfig, problems: { string })
    local spawn = config.spawn
    if not isFinite(spawn.radius) or spawn.radius <= 0 then
        table.insert(problems, "hub spawn.radius must be above 0")
    end
    if not isFinite(spawn.minSpacing) or spawn.minSpacing <= 0 then
        table.insert(problems, "hub spawn.minSpacing must be above 0")
    end
    if not isFinite(spawn.ringGap) or spawn.ringGap <= 0 then
        table.insert(problems, "hub spawn.ringGap must be above 0")
    end
    if spawn.rings < 1 or spawn.rings % 1 ~= 0 then
        table.insert(problems, "hub spawn.rings must be an integer of at least 1")
    end
    if config.serverCap < 1 or config.serverCap > MAX_SERVER_CAP or config.serverCap % 1 ~= 0 then
        table.insert(problems, `hub serverCap must be an integer from 1 to {MAX_SERVER_CAP}`)
    end
    if #problems == 0 and HubLayout.capacity(spawn) < config.serverCap then
        table.insert(
            problems,
            `hub plaza holds {HubLayout.capacity(spawn)} avatars but serverCap is {config.serverCap}`
        )
    end
end

local function validateStations(config: HubConfig, problems: { string })
    local spawn = config.spawn
    local seen: { [string]: boolean } = {}
    local plazaEdge = 0
    if #problems == 0 then
        plazaEdge = spawn.radius + (spawn.rings - 1) * spawn.ringGap + spawn.minSpacing
    end
    for _, station in config.stations do
        local label = `hub station "{station.id}"`
        if station.id == "" or #station.id > 32 then
            table.insert(problems, "a hub station id must be 1 to 32 characters")
        end
        if seen[station.id] then
            table.insert(problems, `{label} is declared twice`)
        end
        seen[station.id] = true
        if station.kind == "" then
            table.insert(problems, `{label} needs a kind`)
        end
        if not isFinite(station.angleDegrees) then
            table.insert(problems, `{label} angleDegrees must be a finite number`)
        end
        if not isFinite(station.radius) or station.radius < plazaEdge then
            table.insert(
                problems,
                `{label} must stand outside the spawn plaza (radius at least {plazaEdge})`
            )
        end
    end
end

--- One human-readable problem per invalid value (empty when valid).
function HubLayout.validate(config: HubConfig): { string }
    local problems: { string } = {}
    if config.id == "" or #config.id > 32 then
        table.insert(problems, "a hub id must be 1 to 32 characters")
    end
    validateSpawn(config, problems)
    local tags = config.nameTags.maxDistance
    if tags ~= tags or tags < 0 then
        table.insert(problems, "hub nameTags.maxDistance must be zero or positive")
    end
    local cooldown = config.emotes.cooldownSeconds
    if cooldown ~= cooldown or cooldown < 0 then
        table.insert(problems, "hub emotes.cooldownSeconds must be zero or positive")
    end
    local seenEmote: { [string]: boolean } = {}
    for _, emote in config.emotes.allowed do
        if emote == "" or seenEmote[emote] then
            table.insert(problems, `hub emote "{emote}" is empty or declared twice`)
        end
        seenEmote[emote] = true
    end
    validateStations(config, problems)
    return problems
end

--- Non-blocking guidance (empty when the layout follows the research). A game may ignore it.
function HubLayout.advise(config: HubConfig): { string }
    local advice: { string } = {}
    if config.serverCap > MEDIAN_SERVER_SIZE * 2 then
        table.insert(
            advice,
            `serverCap {config.serverCap} is over twice the median of {MEDIAN_SERVER_SIZE} players: a crowd hides the avatars the clip must show`
        )
    end
    if config.serverCap == 1 then
        table.insert(
            advice,
            "serverCap 1 is a solo game: the checklist then needs the solo declaration and a funny element that carries the clip"
        )
    end
    if #config.stations == 0 then
        table.insert(advice, "a hub with no station is only a spawn area")
    end
    return advice
end

return HubLayout
