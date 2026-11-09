--!strict
--[[
    Join policy (ADR 0032). Pure: loads under Lune; the clock is injected.

    - `newWait` builds the `Cancel` callback handed to ProfileStore:StartSessionAsync. It says "stop
      waiting" when the player has left, or when our own policy limit passes (the lock holder never
      answered: waiting longer only keeps a player on a frozen screen). ProfileStore polls it.
    - `guard` runs the whole join so that nothing escapes outward: an error becomes a failure
      callback, never a thrown error on the PlayerAdded thread.
]]

export type Wait = {
    -- ProfileStore's `Cancel`: true = stop waiting for the session lock.
    cancel: () -> boolean,
    -- true when the policy limit passed (read from the injected clock, not from a retry count)
    -- and the player is still here.
    timedOut: () -> boolean,
}

export type WaitDeps = {
    clock: () -> number,
    -- true when the player is no longer in the server.
    isGone: () -> boolean,
    maxWaitSeconds: number?,
}

local JoinPolicy = {}

-- Our own limit for a join that waits on a session lock. ProfileStore alone would keep trying
-- up to START_SESSION_TIMEOUT (120 s) and steal at about 45 s.
JoinPolicy.MAX_WAIT_SECONDS = 90

JoinPolicy.KICK_TIMED_OUT =
    "Your data is still in use by another server. Please rejoin in a minute."
JoinPolicy.KICK_UNAVAILABLE =
    "Your saved data could not be opened right now. Please rejoin in a moment."
JoinPolicy.KICK_FAILED = "Could not load your data. Please rejoin."
JoinPolicy.KICK_SESSION_LOST = "Your data session ended on another server. Please rejoin."

function JoinPolicy.newWait(deps: WaitDeps): Wait
    local startedAt = deps.clock()
    local limit = deps.maxWaitSeconds or JoinPolicy.MAX_WAIT_SECONDS
    return {
        cancel = function(): boolean
            if deps.isGone() then
                return true
            end
            return deps.clock() - startedAt >= limit
        end,
        timedOut = function(): boolean
            return not deps.isGone() and deps.clock() - startedAt >= limit
        end,
    }
end

--- The kick text for a join that ended without a profile: the 90 s policy, the store saying the
--- session is unavailable, or any other failure.
function JoinPolicy.kickMessage(timedOut: boolean, failure: string?): string
    if timedOut then
        return JoinPolicy.KICK_TIMED_OUT
    end
    if failure == "session_unavailable" then
        return JoinPolicy.KICK_UNAVAILABLE
    end
    return JoinPolicy.KICK_FAILED
end

--- Runs `body`; an error goes to `onFailure(message)` and `guard` returns false. A failure handler
--- that throws too is reported to `onHandlerError` (the caller logs it; this module stays free of
--- engine globals so it loads under every runtime).
function JoinPolicy.guard(
    body: () -> (),
    onFailure: (message: string) -> (),
    onHandlerError: ((message: string) -> ())?
): boolean
    local failure: string? = nil
    local ok = xpcall(body, function(err: unknown): ()
        failure = tostring(err)
    end)
    if ok then
        return true
    end
    local message = failure or "unknown error"
    local handlerFailure: string? = nil
    local handled = xpcall(function()
        onFailure(message)
    end, function(err: unknown): ()
        handlerFailure = tostring(err)
    end)
    if not handled and onHandlerError ~= nil then
        onHandlerError(`{handlerFailure or "unknown error"} (while handling: {message})`)
    end
    return false
end

return JoinPolicy
