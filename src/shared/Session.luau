--!strict
--[[
    Pure session-lock core for a ProfileStore-style data wrapper (self-written).
    A record holds the player's data plus a lock owner (server JobId) so two servers
    never write the same player at once. Storage is injected via `Backend`, so this
    module loads under Lune; src/server/RobloxDataStoreBackend.luau is the real adapter.
]]

-- Structurally identical to Result.luau (kept local so this file loads under Lune).
export type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

export type SessionRecord<T> = {
    data: T,
    lockOwner: string?,
    lockedAt: number,
    version: number,
}

export type SessionError =
    "locked_by_other_server"
    | "backend_failure"
    | "not_lock_owner"

-- Atomic read-modify-write. `transform` returns nil to abort without writing.
-- Returns the stored record, or nil when the transform aborted.
export type Backend<T> = {
    update: (
        key: string,
        transform: (current: SessionRecord<T>?) -> SessionRecord<T>?
    ) -> Result<SessionRecord<T>?, SessionError>,
}

local Session = {}

--- Pure: decides the record after a lock attempt, or nil when another live server owns it.
function Session.tryLock<T>(
    current: SessionRecord<T>?,
    defaultData: T,
    owner: string,
    now: number,
    staleAfterSeconds: number
): SessionRecord<T>?
    if current == nil then
        return { data = defaultData, lockOwner = owner, lockedAt = now, version = 1 }
    end
    local heldByOther = current.lockOwner ~= nil and current.lockOwner ~= owner
    local stale = now - current.lockedAt >= staleAfterSeconds
    if heldByOther and not stale then
        return nil
    end
    return {
        data = current.data,
        lockOwner = owner,
        lockedAt = now,
        version = current.version + 1,
    }
end

--- Pure: saves new data and optionally releases the lock. nil when the caller is not the owner.
function Session.applySave<T>(
    current: SessionRecord<T>?,
    data: T,
    owner: string,
    now: number,
    release: boolean
): SessionRecord<T>?
    if current == nil or current.lockOwner ~= owner then
        return nil
    end
    return {
        data = data,
        lockOwner = if release then nil else owner,
        lockedAt = now,
        version = current.version + 1,
    }
end

function Session.load<T>(
    backend: Backend<T>,
    key: string,
    defaultData: T,
    owner: string,
    now: number,
    staleAfterSeconds: number
): Result<SessionRecord<T>, SessionError>
    local result = backend.update(key, function(current: SessionRecord<T>?): SessionRecord<T>?
        return Session.tryLock(current, defaultData, owner, now, staleAfterSeconds)
    end)
    if not result.ok then
        return { ok = false, error = result.error }
    end
    local record = result.value
    if record == nil then
        return { ok = false, error = "locked_by_other_server" }
    end
    return { ok = true, value = record }
end

function Session.save<T>(
    backend: Backend<T>,
    key: string,
    data: T,
    owner: string,
    now: number,
    release: boolean
): Result<SessionRecord<T>, SessionError>
    local result = backend.update(key, function(current: SessionRecord<T>?): SessionRecord<T>?
        return Session.applySave(current, data, owner, now, release)
    end)
    if not result.ok then
        return { ok = false, error = result.error }
    end
    local record = result.value
    if record == nil then
        return { ok = false, error = "not_lock_owner" }
    end
    return { ok = true, value = record }
end

return Session
