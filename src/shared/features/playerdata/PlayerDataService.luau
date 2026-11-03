--!strict
--[[
    Tracks the loaded profile of each online player. Pure: loads under Lune; the repository
    (ProfileStore in production, the in-memory fake in tests) is injected.
    The server Main calls `join` on PlayerAdded and `leave` on PlayerRemoving.
]]

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

type ProfileError = "session_unavailable" | "not_active" | "save_failed"

type ProfileHandle<T> = {
    key: string,
    data: T,
    isActive: (self: ProfileHandle<T>) -> boolean,
    save: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    release: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    onSessionEnd: (self: ProfileHandle<T>, listener: () -> ()) -> (),
}

type ProfileRepository<T> = {
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

export type Deps<T> = {
    repository: ProfileRepository<T>,
    -- Called when a session ends without `leave` (another server took the profile).
    onSessionLost: (key: string) -> (),
}

export type PlayerDataService<T> = {
    join: (self: PlayerDataService<T>, key: string) -> Result<T, ProfileError>,
    leave: (self: PlayerDataService<T>, key: string) -> Result<nil, ProfileError>,
    -- nil when the player's data is not loaded.
    get: (self: PlayerDataService<T>, key: string) -> T?,
}

local PlayerDataServiceModule = {}

function PlayerDataServiceModule.new<T>(deps: Deps<T>): PlayerDataService<T>
    local handles: { [string]: ProfileHandle<T> } = {}

    local service: PlayerDataService<T> = {
        join = function(_self: PlayerDataService<T>, key: string): Result<T, ProfileError>
            if handles[key] ~= nil then
                return { ok = false, error = "session_unavailable" }
            end
            local loaded = deps.repository:load(key)
            if not loaded.ok then
                return { ok = false, error = loaded.error }
            end
            local handle = loaded.value
            handles[key] = handle
            handle:onSessionEnd(function()
                if handles[key] == handle then
                    handles[key] = nil
                    deps.onSessionLost(key)
                end
            end)
            return { ok = true, value = handle.data }
        end,
        leave = function(_self: PlayerDataService<T>, key: string): Result<nil, ProfileError>
            local handle = handles[key]
            if handle == nil then
                return { ok = false, error = "not_active" }
            end
            handles[key] = nil
            return handle:release()
        end,
        get = function(_self: PlayerDataService<T>, key: string): T?
            local handle = handles[key]
            if handle == nil then
                return nil
            end
            return handle.data
        end,
    }
    return service
end

return PlayerDataServiceModule
