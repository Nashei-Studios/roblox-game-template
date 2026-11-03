--!strict
--[[
    Adapter: ProfileRepository<T> over ProfileStore (vendor/ProfileStore, ADR 0010).
    ProfileStore owns session locking, autosave, retries and release on shutdown; this file
    only translates its Profile object to the typed port. Not unit-testable under Lune (it
    needs the engine); the port contract is tested against the in-memory fake.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileRepository = require(ReplicatedStorage.Shared.ports.ProfileRepository)

type ProfileError = ProfileRepository.ProfileError
type Result<T, E> = ProfileRepository.Result<T, E>

-- The slice of ProfileStore's Profile that this adapter uses.
export type ProfileLike<T> = {
    Data: T,
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

local ProfileStoreRepository = {}

function ProfileStoreRepository.new<T>(store: StoreLike<T>): ProfileRepository.ProfileRepository<T>
    local repository: ProfileRepository.ProfileRepository<T> = {
        load = function(
            _self: ProfileRepository.ProfileRepository<T>,
            key: string
        ): Result<ProfileRepository.ProfileHandle<T>, ProfileError>
            local profile = store:StartSessionAsync(key, nil)
            if profile == nil then
                return { ok = false, error = "session_unavailable" }
            end
            -- Fill fields added to the template since this profile was last saved.
            profile:Reconcile()

            local handle: ProfileRepository.ProfileHandle<T> = {
                key = key,
                data = profile.Data,
                isActive = function(_handle: ProfileRepository.ProfileHandle<T>): boolean
                    return profile:IsActive()
                end,
                save = function(
                    _handle: ProfileRepository.ProfileHandle<T>
                ): Result<nil, ProfileError>
                    if not profile:IsActive() then
                        return { ok = false, error = "not_active" }
                    end
                    -- Save is asynchronous; ProfileStore reports failures through its OnError signal.
                    profile:Save()
                    return { ok = true, value = nil }
                end,
                release = function(
                    _handle: ProfileRepository.ProfileHandle<T>
                ): Result<nil, ProfileError>
                    if not profile:IsActive() then
                        return { ok = false, error = "not_active" }
                    end
                    profile:EndSession()
                    return { ok = true, value = nil }
                end,
                onSessionEnd = function(
                    _handle: ProfileRepository.ProfileHandle<T>,
                    listener: () -> ()
                )
                    profile.OnSessionEnd:Connect(listener)
                end,
            }
            return { ok = true, value = handle }
        end,
    }
    return repository
end

return ProfileStoreRepository
