--!strict
--[[
    The board of the presence feed (ADR 0053): picks what a wall shows from the live entries and
    words it from the templates of each kind. Pure; the server publishes `encode` and the client
    calls `decode` and `rows`. Placeholders in a template: {name}, {value}, {ago}.
]]

local PresenceConfig = require("./PresenceConfig")
local PresenceEntry = require("./PresenceEntry")

export type Entry = PresenceEntry.Entry

-- The picked entries, in the order of the declared kinds.
export type Board = { entries: { Entry } }

export type Row = {
    -- Who and how much, the part that has to read from a few studs away.
    headline: string,
    -- What it was and how long ago.
    detail: string,
}

local PresenceBoard = {}

--- Picks the entries to show from entries newest first. `now` drops expired ones.
function PresenceBoard.build(
    entries: { Entry },
    now: number,
    config: PresenceConfig.PresenceConfig
): Board
    local picked: { Entry } = {}
    for _, kind in config.kinds do
        local best: Entry? = nil
        local newest: { Entry } = {}
        for _, entry in entries do
            if entry.kind == kind.id and now - entry.at < config.ttlSeconds then
                if kind.pick == "max" then
                    if best == nil or entry.value > best.value then
                        best = entry
                    end
                elseif #newest < kind.rows then
                    table.insert(newest, entry)
                end
            end
        end
        if best ~= nil then
            table.insert(picked, best)
        end
        for _, entry in newest do
            table.insert(picked, entry)
        end
    end
    return { entries = picked }
end

--- "now", "5m ago", "3h ago".
function PresenceBoard.ago(seconds: number): string
    if seconds < 60 then
        return "now"
    elseif seconds < 3600 then
        return `{math.floor(seconds / 60)}m ago`
    end
    return `{math.floor(seconds / 3600)}h ago`
end

--- The text the server replicates: the picked entries, one per line.
function PresenceBoard.encode(board: Board): string
    local parts: { string } = {}
    for _, entry in board.entries do
        table.insert(parts, PresenceEntry.encode(entry))
    end
    return table.concat(parts, "\n")
end

--- Reads replicated text back into entries; malformed lines are skipped.
function PresenceBoard.decode(text: string): { Entry }
    local entries: { Entry } = {}
    for line in string.gmatch(text, "[^\n]+") do
        local entry = PresenceEntry.decode(line)
        if entry ~= nil then
            table.insert(entries, entry)
        end
    end
    return entries
end

local function fill(template: string, entry: Entry, ago: string): string
    local text = string.gsub(template, "{name}", function()
        return entry.name
    end)
    text = string.gsub(text, "{value}", function()
        return tostring(entry.value)
    end)
    text = string.gsub(text, "{ago}", function()
        return ago
    end)
    return text
end

--- Display rows, each with its time ago; one empty-state row when nothing is live. Entries of
--- an undeclared kind are skipped.
function PresenceBoard.rows(
    entries: { Entry },
    now: number,
    config: PresenceConfig.PresenceConfig
): { Row }
    local byKind: { [string]: PresenceConfig.KindDef } = {}
    for _, kind in config.kinds do
        byKind[kind.id] = kind
    end
    local rows: { Row } = {}
    for _, entry in entries do
        local kind = byKind[entry.kind]
        if kind ~= nil then
            local ago = PresenceBoard.ago(now - entry.at)
            table.insert(rows, {
                headline = fill(kind.headline, entry, ago),
                detail = fill(kind.detail, entry, ago),
            })
        end
    end
    if #rows == 0 then
        table.insert(rows, { headline = config.emptyHeadline, detail = config.emptyDetail })
    end
    return rows
end

return PresenceBoard
