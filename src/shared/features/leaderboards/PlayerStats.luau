--!strict
--[[
    Reads the stats a board can rank from the player's profile. Pure: loads under Lune.
    Leaderstats and boards are VIEWS of PlayerData, never the source of truth: nothing here
    writes to the profile.
]]

export type StatProfile = { coins: number, sessionCount: number }

-- Game-defined stats injected by the server (not saved in the profile), keyed by the names in
-- LeaderboardsConfig.extraStats.
export type ExtraStats = { [string]: number }

local PlayerStats = {}

--- The integer value of `stat` (a key of LeaderboardsConfig.STATS), or nil for an unknown stat.
function PlayerStats.read(profile: StatProfile, stat: string, extra: ExtraStats?): number?
    local raw: number? = nil
    if stat == "coins" then
        raw = profile.coins
    elseif stat == "sessions" then
        raw = profile.sessionCount
    elseif extra ~= nil then
        raw = extra[stat]
    end
    if raw == nil or raw ~= raw then
        return nil
    end
    return math.max(0, math.floor(raw))
end

return PlayerStats
