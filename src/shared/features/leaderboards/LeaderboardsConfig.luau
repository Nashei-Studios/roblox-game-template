--!strict
--[[
    Typed config of the leaderboards and its validation. Pure: loads under Lune. Every value
    (boards, stats, cadences) lives in Config.default.leaderboards.

    Limits baked into `validate` (docs: OrderedDataStore / GetSortedAsync request budget):
    GetSortedAsync allows 5 requests per minute per server plus 2 per player. Reads here are
    never made per join, only on a fixed schedule, so the budget that matters is the fixed part:
    the sum over boards of (60 / refreshSeconds) must stay at or under 5.
]]

local RewardConfig = require("../rewards/RewardConfig")

export type ResetCycle = "never" | "daily" | "weekly"

export type BoardConfig = {
    -- Which player stat the board ranks (a key of LeaderboardsConfig.STATS).
    stat: string,
    -- Seconds between two reads of the top. At least MIN_REFRESH_SECONDS.
    refreshSeconds: number,
    -- How many places the board keeps and shows (1 to MAX_SIZE).
    size: number,
    -- "never" keeps one all-time list; "daily" and "weekly" start a new list each UTC period.
    resetCycle: ResetCycle,
}

export type LeaderboardsConfig = {
    -- Stats shown as leaderstats next to the player name (at most MAX_LEADERSTATS).
    leaderstats: { string },
    -- Seconds between two rounds of score writes. At least MIN_WRITE_SECONDS.
    writeSeconds: number,
    -- Board id -> board. The id is 1 to MAX_ID_LENGTH characters.
    boards: { [string]: BoardConfig },
}

local LeaderboardsConfigModule = {}

-- Stats a board or leaderstat can show; PlayerStats reads them from the profile.
LeaderboardsConfigModule.STATS = { "coins", "sessions" } :: { string }

LeaderboardsConfigModule.MAX_LEADERSTATS = 4 -- sourced: the player list shows up to four stats
LeaderboardsConfigModule.MAX_SIZE = 100 -- chosen, not sourced: a podium and a page of ranks
LeaderboardsConfigModule.MAX_ID_LENGTH = 24 -- chosen: the store name stays under the 50 character limit
LeaderboardsConfigModule.MIN_REFRESH_SECONDS = 60 -- chosen, not sourced: keeps the 5 per minute read budget
LeaderboardsConfigModule.MIN_WRITE_SECONDS = 30 -- chosen, not sourced
LeaderboardsConfigModule.SORTED_READS_PER_MINUTE = 5 -- sourced: GetSortedAsync server base budget

local CYCLES: { [string]: boolean } = { never = true, daily = true, weekly = true }

local function isKnownStat(stat: string): boolean
    return table.find(LeaderboardsConfigModule.STATS, stat) ~= nil
end

--- Board ids in a stable order (map iteration order is not).
function LeaderboardsConfigModule.sortedIds(config: LeaderboardsConfig): { string }
    local ids: { string } = {}
    for id in config.boards do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

--- One human-readable problem per invalid value (empty when valid).
function LeaderboardsConfigModule.validate(config: LeaderboardsConfig): { string }
    local problems: { string } = {}
    if #config.leaderstats > LeaderboardsConfigModule.MAX_LEADERSTATS then
        table.insert(
            problems,
            `leaderboards.leaderstats shows at most {LeaderboardsConfigModule.MAX_LEADERSTATS} stats`
        )
    end
    local seenStats: { [string]: boolean } = {}
    for _, stat in config.leaderstats do
        if not isKnownStat(stat) then
            table.insert(problems, `leaderboards.leaderstats has unknown stat "{stat}"`)
        end
        if seenStats[stat] then
            table.insert(problems, `leaderboards.leaderstats lists "{stat}" twice`)
        end
        seenStats[stat] = true
    end
    local writeSeconds = config.writeSeconds
    if
        not RewardConfig.isFinite(writeSeconds)
        or writeSeconds < LeaderboardsConfigModule.MIN_WRITE_SECONDS
    then
        table.insert(
            problems,
            `leaderboards.writeSeconds must be at least {LeaderboardsConfigModule.MIN_WRITE_SECONDS}`
        )
    end
    local readsPerMinute = 0
    for _, id in LeaderboardsConfigModule.sortedIds(config) do
        local board = config.boards[id]
        if id == "" or #id > LeaderboardsConfigModule.MAX_ID_LENGTH then
            table.insert(
                problems,
                `leaderboards board id "{id}" must be 1 to {LeaderboardsConfigModule.MAX_ID_LENGTH} characters`
            )
        end
        if string.match(id, "^[%w_]*$") == nil then
            table.insert(
                problems,
                `leaderboards board id "{id}" may only use letters, digits and _`
            )
        end
        if not isKnownStat(board.stat) then
            table.insert(problems, `leaderboard "{id}" ranks unknown stat "{board.stat}"`)
        end
        if not CYCLES[board.resetCycle] then
            table.insert(problems, `leaderboard "{id}" has an unknown resetCycle`)
        end
        local size = board.size
        if not RewardConfig.isPositiveInteger(size) or size > LeaderboardsConfigModule.MAX_SIZE then
            table.insert(
                problems,
                `leaderboard "{id}" size must be an integer from 1 to {LeaderboardsConfigModule.MAX_SIZE}`
            )
        end
        local refresh = board.refreshSeconds
        if
            not RewardConfig.isFinite(refresh)
            or refresh < LeaderboardsConfigModule.MIN_REFRESH_SECONDS
        then
            table.insert(
                problems,
                `leaderboard "{id}" refreshSeconds must be at least {LeaderboardsConfigModule.MIN_REFRESH_SECONDS}`
            )
        else
            readsPerMinute += 60 / refresh
        end
    end
    if readsPerMinute > LeaderboardsConfigModule.SORTED_READS_PER_MINUTE then
        table.insert(
            problems,
            `leaderboards read {readsPerMinute} sorted pages per minute; the budget is {LeaderboardsConfigModule.SORTED_READS_PER_MINUTE}`
        )
    end
    return problems
end

return LeaderboardsConfigModule
