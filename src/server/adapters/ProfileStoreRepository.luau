--!strict
--[[
    Adapter: ProfileRepository<T> over ProfileStore (vendor/ProfileStore, ADR 0010).
    ProfileStore owns session locking, autosave, retries and release on shutdown; this file
    only translates its Profile object to the typed port. The store is injected, so it loads
    under Lune and is tested with a fake store; behavior against the real ProfileStore is R4
    (Luau Execution API).
]]

-- Structurally identical to ports/ProfileRepository.luau (kept local so this file loads under
-- Lune; the compiler checks the match where Main.server hands the repository to the service).
type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

type ProfileError = "session_unavailable" | "not_active" | "save_failed"

type SaveConfirmError = "not_active" | "timeout"

type ProfileHandle<T> = {
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

type ProfileRepository<T> = {
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

-- The slice of ProfileStore's Profile that this adapter uses.
export type ProfileLike<T> = {
    Data: T,
    -- Last snapshot that ProfileStore confirmed written to the DataStore (a table replaced
    -- after every successful save; read it fresh each time).
    LastSavedData: T,
    IsActive: (self: unknown) -> boolean,
    Reconcile: (self: unknown) -> (),
    Save: (self: unknown) -> (),
    EndSession: (self: unknown) -> (),
    OnSessionEnd: {
        Connect: (self: unknown, listener: () -> ()) -> unknown,
    },
}

-- The slice of ProfileStore's store object that this adapter uses.
export type StoreLike<T> = {
    StartSessionAsync: (
        self: unknown,
        profileKey: string,
        params: { Steal: boolean? }?
    ) -> ProfileLike<T>?,
}

-- Time and yielding come from the composition root (os.clock and task.wait there), so the
-- confirmation loop runs under Lune with a fake clock.
export type Runtime = {
    clock: () -> number,
    wait: (seconds: number) -> (),
}

local POLL_SECONDS = 0.1
-- A save already in flight when we ask may predate the data we want confirmed, so ask again.
-- At most one Save() per profile per interval, however many receipts wait (ADR 0016, Budget).
local SAVE_RETRY_SECONDS = 5

local ProfileStoreRepository = {}

function ProfileStoreRepository.new<T>(store: StoreLike<T>, runtime: Runtime): ProfileRepository<T>
    local repository: ProfileRepository<T> = {
        load = function(
            _self: ProfileRepository<T>,
            key: string
        ): Result<ProfileHandle<T>, ProfileError>
            local profile = store:StartSessionAsync(key, nil)
            if profile == nil then
                return { ok = false, error = "session_unavailable" }
            end
            -- Fill fields added to the template since this profile was last saved.
            profile:Reconcile()
            -- Shared by every confirmSaved wait on this profile: ProfileStore does not coalesce
            -- Save() calls (each one is an UpdateAsync), so concurrent receipts must share them.
            local lastSaveRequestedAt = -math.huge

            local handle: ProfileHandle<T> = {
                key = key,
                data = profile.Data,
                isActive = function(_handle: ProfileHandle<T>): boolean
                    return profile:IsActive()
                end,
                save = function(_handle: ProfileHandle<T>): Result<nil, ProfileError>
                    if not profile:IsActive() then
                        return { ok = false, error = "not_active" }
                    end
                    -- Save is asynchronous; ProfileStore reports failures through its OnError signal.
                    profile:Save()
                    return { ok = true, value = nil }
                end,
                release = function(_handle: ProfileHandle<T>): Result<nil, ProfileError>
                    if not profile:IsActive() then
                        return { ok = false, error = "not_active" }
                    end
                    profile:EndSession()
                    return { ok = true, value = nil }
                end,
                confirmSaved = function(
                    _handle: ProfileHandle<T>,
                    isSaved: (saved: T) -> boolean,
                    timeoutSeconds: number
                ): Result<nil, SaveConfirmError>
                    local deadline = runtime.clock() + timeoutSeconds
                    while true do
                        -- Official ProfileStore pattern: LastSavedData is the confirmed snapshot
                        -- and survives the session ending, so check it before IsActive.
                        if isSaved(profile.LastSavedData) then
                            return { ok = true, value = nil }
                        end
                        if not profile:IsActive() then
                            return { ok = false, error = "not_active" }
                        end
                        local now = runtime.clock()
                        if now >= deadline then
                            return { ok = false, error = "timeout" }
                        end
                        if now - lastSaveRequestedAt >= SAVE_RETRY_SECONDS then
                            profile:Save()
                            lastSaveRequestedAt = now
                        end
                        runtime.wait(POLL_SECONDS)
                    end
                end,
                onSessionEnd = function(_handle: ProfileHandle<T>, listener: () -> ())
                    profile.OnSessionEnd:Connect(listener)
                end,
            }
            return { ok = true, value = handle }
        end,
    }
    return repository
end

return ProfileStoreRepository
