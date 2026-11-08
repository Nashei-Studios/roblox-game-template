--!strict
--[[
    Picks the DataStore name for player profiles (ADR 0043). Pure: loads under Lune.
    Studio gets its own store so a playtest never takes the live profile's session lock.
]]

export type DataConfig = { profileStore: string, studioProfileStore: string }

local ProfileStoreName = {}

function ProfileStoreName.pick(isStudio: boolean, config: DataConfig): string
    return if isStudio then config.studioProfileStore else config.profileStore
end

return ProfileStoreName
