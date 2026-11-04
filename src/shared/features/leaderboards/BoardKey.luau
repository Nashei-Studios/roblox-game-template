--!strict
--[[
    Pure helpers for board storage keys and the wire text of a published board.
    Loads under Lune. A reset cycle is a new list per UTC period, so the old list is simply no
    longer read (no delete needed); weeks start on Monday.
]]

local LeaderboardsConfig = require("./LeaderboardsConfig")

export type Entry = { userId: number, value: number }

local SECONDS_PER_DAY = 86400
-- 1970-01-01 was a Thursday: shifting by 3 days makes a week start on Monday.
local MONDAY_SHIFT_DAYS = 3

local BoardKey = {}

--- The UTC period number of `now` (Unix seconds) for a reset cycle; always 0 for "never".
function BoardKey.period(cycle: LeaderboardsConfig.ResetCycle, now: number): number
    local day = math.floor(now / SECONDS_PER_DAY)
    if cycle == "daily" then
        return day
    elseif cycle == "weekly" then
        return math.floor((day + MONDAY_SHIFT_DAYS) / 7)
    end
    return 0
end

--- The store key of a board in the current period, for example "Coins" or "Coins_w2931".
function BoardKey.storeKey(
    boardId: string,
    cycle: LeaderboardsConfig.ResetCycle,
    now: number
): string
    if cycle == "never" then
        return boardId
    end
    local tag = if cycle == "daily" then "d" else "w"
    return `{boardId}_{tag}{BoardKey.period(cycle, now)}`
end

--- "userId:value;userId:value" for the replicated board value.
function BoardKey.encode(entries: { Entry }): string
    local parts: { string } = {}
    for _, entry in entries do
        table.insert(parts, `{entry.userId}:{entry.value}`)
    end
    return table.concat(parts, ";")
end

--- Reads the text written by `encode`; malformed pieces are skipped.
function BoardKey.decode(text: string): { Entry }
    local entries: { Entry } = {}
    for piece in string.gmatch(text, "[^;]+") do
        local userText, valueText = string.match(piece, "^(%d+):(%d+)$")
        local userId = tonumber(userText)
        local value = tonumber(valueText)
        if userId ~= nil and value ~= nil then
            table.insert(entries, { userId = userId, value = value })
        end
    end
    return entries
end

--- Reads the text a ReplicatedBoardPublisher wrote: "entries|updatedAt". Entries are empty when
--- the text is malformed; updatedAt is 0 when missing.
function BoardKey.decodePublished(text: string): ({ Entry }, number)
    local body, stamp = string.match(text, "^(.-)|(%d+)$")
    if body == nil or stamp == nil then
        return BoardKey.decode(text), 0
    end
    return BoardKey.decode(body), tonumber(stamp) or 0
end

return BoardKey
