--!strict
--[[
    In-memory ProfileRepository: the fake used by tests and by Lune-based dev runs.
    Emulates session locking per key; stored data survives release, like a DataStore would.
    `clone` copies a data table so a released handle cannot mutate stored data.
]]

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

type ProfileError = "session_unavailable" | "not_active" | "save_failed"

export type SaveConfirmError = "not_active" | "timeout"

export type ProfileHandle<T> = {
    key: string,
    data: T,
    isActive: (self: ProfileHandle<T>) -> boolean,
    save: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    release: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    onSessionEnd: (self: ProfileHandle<T>, listener: () -> ()) -> (),
    -- Yields until a saved snapshot satisfies `isSaved` (a confirmed DataStore write), the
    -- session ends without it ("not_active") or `timeoutSeconds` pass ("timeout"). Used to
    -- confirm that a purchase reached the DataStore before Roblox is told it was granted.
    confirmSaved: (
        self: ProfileHandle<T>,
        isSaved: (saved: T) -> boolean,
        timeoutSeconds: number
    ) -> Result<nil, SaveConfirmError>,
}

export type ProfileRepository<T> = {
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

export type Deps<T> = {
    default: () -> T,
    clone: (data: T) -> T,
    -- Tests: while this returns true, `save` reports success but nothing reaches storage
    -- (a DataStore outage), so `confirmSaved` times out.
    failSaves: (() -> boolean)?,
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
            -- Stands in for Profile.LastSavedData: the last snapshot that reached storage.
            local lastSaved: T = deps.clone(data)
            local function persist(current: T)
                local failing = deps.failSaves
                if failing ~= nil and failing() then
                    return
                end
                stored[key] = deps.clone(current)
                lastSaved = deps.clone(current)
            end
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
                    persist(self.data)
                    return { ok = true, value = nil }
                end,
                release = function(self: ProfileHandle<T>): Result<nil, ProfileError>
                    if not active then
                        return { ok = false, error = "not_active" }
                    end
                    stored[key] = deps.clone(self.data)
                    lastSaved = deps.clone(self.data)
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
                confirmSaved = function(
                    self: ProfileHandle<T>,
                    isSaved: (saved: T) -> boolean,
                    _timeoutSeconds: number
                ): Result<nil, SaveConfirmError>
                    if isSaved(lastSaved) then
                        return { ok = true, value = nil }
                    end
                    if not active then
                        return { ok = false, error = "not_active" }
                    end
                    persist(self.data)
                    if isSaved(lastSaved) then
                        return { ok = true, value = nil }
                    end
                    -- No clock in the fake: the timeout is reported at once.
                    return { ok = false, error = "timeout" }
                end,
            }
            return { ok = true, value = handle }
        end,
    }
    return repository
end

return InMemoryProfileRepository
