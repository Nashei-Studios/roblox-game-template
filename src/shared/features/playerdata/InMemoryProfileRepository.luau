--!strict
--[[
    In-memory ProfileRepository: the fake used by tests and by Lune-based dev runs.
    Emulates session locking per key; stored data survives release, like a DataStore would.
    `clone` copies a data table so a released handle cannot mutate stored data.
]]

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

type ProfileError = "session_unavailable" | "not_active" | "save_failed"

export type ProfileHandle<T> = {
    key: string,
    data: T,
    isActive: (self: ProfileHandle<T>) -> boolean,
    save: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    release: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    onSessionEnd: (self: ProfileHandle<T>, listener: () -> ()) -> (),
}

export type ProfileRepository<T> = {
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

export type Deps<T> = {
    default: () -> T,
    clone: (data: T) -> T,
}

local InMemoryProfileRepository = {}

function InMemoryProfileRepository.new<T>(deps: Deps<T>): ProfileRepository<T>
    local stored: { [string]: T } = {}
    local locked: { [string]: boolean } = {}

    local repository: ProfileRepository<T> = {
        load = function(
            _self: ProfileRepository<T>,
            key: string
        ): Result<ProfileHandle<T>, ProfileError>
            if locked[key] == true then
                return { ok = false, error = "session_unavailable" }
            end
            locked[key] = true
            local existing = stored[key]
            local data = if existing ~= nil then deps.clone(existing) else deps.default()
            local active = true
            local listeners: { () -> () } = {}

            local handle: ProfileHandle<T> = {
                key = key,
                data = data,
                isActive = function(_handle: ProfileHandle<T>): boolean
                    return active
                end,
                save = function(self: ProfileHandle<T>): Result<nil, ProfileError>
                    if not active then
                        return { ok = false, error = "not_active" }
                    end
                    stored[key] = deps.clone(self.data)
                    return { ok = true, value = nil }
                end,
                release = function(self: ProfileHandle<T>): Result<nil, ProfileError>
                    if not active then
                        return { ok = false, error = "not_active" }
                    end
                    stored[key] = deps.clone(self.data)
                    active = false
                    locked[key] = nil
                    for _, listener in listeners do
                        listener()
                    end
                    return { ok = true, value = nil }
                end,
                onSessionEnd = function(_handle: ProfileHandle<T>, listener: () -> ())
                    table.insert(listeners, listener)
                end,
            }
            return { ok = true, value = handle }
        end,
    }
    return repository
end

return InMemoryProfileRepository
