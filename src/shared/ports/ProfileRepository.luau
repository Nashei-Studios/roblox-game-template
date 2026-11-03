--!strict
--[[
    Port: player data persistence with session locking (ADR 0010).
    Implementations: src/server/adapters/ProfileStoreRepository.luau (ProfileStore) and
    src/shared/features/playerdata/InMemoryProfileRepository.luau (tests, dev).
    Both must pass tests/features/playerdata/ProfileRepository.contract.luau.
]]

-- Structurally identical to Result.luau (kept local so this file loads under Lune).
export type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

export type ProfileError = "session_unavailable" | "not_active" | "save_failed"

export type ProfileHandle<T> = {
    key: string,
    -- Live table: mutate it, then save. Only valid while the handle is active.
    data: T,
    isActive: (self: ProfileHandle<T>) -> boolean,
    save: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    -- Saves a last time and releases the session lock.
    release: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    -- Fires when the session ends for any reason (release, or another server took it).
    onSessionEnd: (self: ProfileHandle<T>, listener: () -> ()) -> (),
}

export type ProfileRepository<T> = {
    -- Yields. Starts a locked session for `key`; "session_unavailable" when it cannot.
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

return {}
