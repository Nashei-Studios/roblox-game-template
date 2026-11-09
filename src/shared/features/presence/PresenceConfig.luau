--!strict
--[[
    Typed config of the presence board (ADR 0053) and its validation. Pure: loads under Lune.
    Every number carries its provenance: "sourced" quotes Roblox documentation, "chosen" is a
    budget. The game declares its own entry kinds and the wording of each row; the mold knows
    no game word.
]]

export type KindDef = {
    -- Short id stored in the feed: letters, digits and underscore.
    id: string,
    -- "max" keeps the entry with the highest value; "newest" lists the newest `rows` entries.
    pick: string,
    -- Rows on the board (1 for "max" kinds).
    rows: number,
    -- Row wording with {name}, {value} and {ago} placeholders.
    headline: string,
    detail: string,
}

export type PresenceConfig = {
    kinds: { KindDef },
    -- Entries the shared feed keeps (the oldest are removed past this).
    maxEntries: number,
    -- Seconds an entry lives in the store and on the board.
    ttlSeconds: number,
    -- Seconds a server serves its cached read before asking the store again.
    readCacheSeconds: number,
    -- Minimum seconds between two entries of the same player and kind.
    minGapSeconds: number,
    -- Longest name kept on an entry.
    maxNameLength: number,
    -- Shown when nothing is live.
    emptyHeadline: string,
    emptyDetail: string,
}

local PresenceConfigModule = {}

-- sourced: MemoryStore items expire after at most 45 days.
PresenceConfigModule.MAX_STORE_TTL_SECONDS = 3888000
-- chosen: keeps reads far below the per-server budget.
PresenceConfigModule.MIN_READ_CACHE_SECONDS = 10

--- Neutral numbers; the game adds its kinds. The caps are the ones game 1 shipped.
function PresenceConfigModule.defaults(kinds: { KindDef }): PresenceConfig
    return {
        kinds = kinds,
        maxEntries = 100,
        ttlSeconds = 86400,
        readCacheSeconds = 30,
        minGapSeconds = 60,
        maxNameLength = 20, -- sourced: Roblox usernames are 3 to 20 characters
        emptyHeadline = "Quiet right now",
        emptyDetail = "Be the first on the board",
    }
end

--- Reasons the config cannot run (empty = valid).
function PresenceConfigModule.problems(config: PresenceConfig): { string }
    local found: { string } = {}
    if #config.kinds == 0 then
        table.insert(found, "at least one kind is needed")
    end
    local seen: { [string]: boolean } = {}
    for _, kind in config.kinds do
        if string.match(kind.id, "^[%w_]+$") == nil or #kind.id > 24 then
            table.insert(found, `kind id "{kind.id}" must be 1 to 24 letters, digits or _`)
        end
        if seen[kind.id] then
            table.insert(found, `kind "{kind.id}" is declared twice`)
        end
        seen[kind.id] = true
        if kind.pick ~= "max" and kind.pick ~= "newest" then
            table.insert(found, `kind "{kind.id}" pick must be "max" or "newest"`)
        end
        if kind.rows < 1 or kind.rows > 5 or kind.rows % 1 ~= 0 then
            table.insert(found, `kind "{kind.id}" rows must be 1 to 5`)
        end
        if kind.pick == "max" and kind.rows ~= 1 then
            table.insert(found, `kind "{kind.id}" is "max" and shows one row`)
        end
        if kind.headline == "" or kind.detail == "" then
            table.insert(found, `kind "{kind.id}" needs a headline and a detail`)
        end
    end
    if config.maxEntries < 3 or config.maxEntries > 1000 then
        table.insert(found, "maxEntries must be 3 to 1000")
    end
    if config.ttlSeconds < 60 or config.ttlSeconds > PresenceConfigModule.MAX_STORE_TTL_SECONDS then
        table.insert(found, "ttlSeconds is outside the store limit")
    end
    if config.readCacheSeconds < PresenceConfigModule.MIN_READ_CACHE_SECONDS then
        table.insert(found, "readCacheSeconds is too low for the read budget")
    end
    if config.minGapSeconds < 0 then
        table.insert(found, "minGapSeconds cannot be negative")
    end
    if config.maxNameLength < 3 then
        table.insert(found, "maxNameLength must be at least 3")
    end
    if config.emptyHeadline == "" or config.emptyDetail == "" then
        table.insert(found, "the empty state needs a headline and a detail")
    end
    return found
end

return PresenceConfigModule
