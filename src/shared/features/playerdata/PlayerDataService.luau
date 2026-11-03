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

export type Deps<T, E> = {
    repository: ProfileRepository<T>,
    -- Called when a session ends without `leave` (another server took the profile).
    onSessionLost: (key: string) -> (),
    -- Brings freshly loaded data to the current schema IN PLACE (the table is the live
    -- profile data) or fails with a typed error. Production: PlayerDataMigrations.migrateInPlace.
    migrate: (data: T) -> Result<T, E>,
    -- Records the start of a session on the migrated data and returns its 1-based index.
    startSession: (data: T) -> number,
}

export type Joined<T> = {
    data: T,
    -- How many sessions this player has started, counting this one.
    sessionIndex: number,
}

export type PlayerDataService<T, E> = {
    join: (self: PlayerDataService<T, E>, key: string) -> Result<Joined<T>, ProfileError | E>,
    leave: (self: PlayerDataService<T, E>, key: string) -> Result<nil, ProfileError>,
    -- nil when the player's data is not loaded.
    get: (self: PlayerDataService<T, E>, key: string) -> T?,
}

local PlayerDataServiceModule = {}

function PlayerDataServiceModule.new<T, E>(deps: Deps<T, E>): PlayerDataService<T, E>
    local handles: { [string]: ProfileHandle<T> } = {}

    local service: PlayerDataService<T, E> = {
        join = function(
            _self: PlayerDataService<T, E>,
            key: string
        ): Result<Joined<T>, ProfileError | E>
            if handles[key] ~= nil then
                return { ok = false, error = "session_unavailable" }
            end
            local loaded = deps.repository:load(key)
            if not loaded.ok then
                return { ok = false, error = loaded.error }
            end
            local handle = loaded.value
            local migrated = deps.migrate(handle.data)
            if not migrated.ok then
                -- Never expose data we cannot read; free the lock so another (newer) server can use it.
                local released = handle:release()
                if not released.ok then
                    warn(`Could not release {key} after a failed migration: {released.error}`)
                end
                return { ok = false, error = migrated.error }
            end
            handles[key] = handle
            handle:onSessionEnd(function()
                if handles[key] == handle then
                    handles[key] = nil
                    deps.onSessionLost(key)
                end
            end)
            local sessionIndex = deps.startSession(migrated.value)
            return { ok = true, value = { data = migrated.value, sessionIndex = sessionIndex } }
        end,
        leave = function(_self: PlayerDataService<T, E>, key: string): Result<nil, ProfileError>
            local handle = handles[key]
            if handle == nil then
                return { ok = false, error = "not_active" }
            end
            handles[key] = nil
            return handle:release()
        end,
        get = function(_self: PlayerDataService<T, E>, key: string): T?
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
