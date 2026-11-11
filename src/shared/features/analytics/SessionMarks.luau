--!strict
--[[
    Fires `session_5min` once per session, SESSION_MARK_SECONDS after the player joined, if the
    player is still in (ADR 0064). Pure: the scheduler and the presence check are injected, so
    this loads under Lune and is tested with a fake clock.
]]

local Analytics = require("./Analytics")

export type Tracker = {
    track: (self: Tracker, name: string, userId: number, sessionIndex: number) -> boolean,
}

export type Deps = {
    tracker: Tracker,
    -- Runs `callback` once after `seconds` (task.delay in the composition root).
    delay: (seconds: number, callback: () -> ()) -> (),
    isPresent: (userId: number) -> boolean,
}

export type SessionMarks = {
    -- Starts the timer of a session. Calling it again for the same session does nothing.
    start: (self: SessionMarks, userId: number, sessionIndex: number) -> (),
    -- Drops the session so a later join starts a fresh timer.
    forget: (self: SessionMarks, userId: number) -> (),
}

local SessionMarksModule = {}

function SessionMarksModule.new(deps: Deps): SessionMarks
    -- userId -> sessionIndex whose timer is armed or already fired.
    local armed: { [number]: number } = {}
    local marks: SessionMarks = {
        start = function(_self: SessionMarks, userId: number, sessionIndex: number)
            if armed[userId] == sessionIndex then
                return
            end
            armed[userId] = sessionIndex
            deps.delay(Analytics.SESSION_MARK_SECONDS, function()
                if armed[userId] == sessionIndex and deps.isPresent(userId) then
                    deps.tracker:track("session_5min", userId, sessionIndex)
                end
            end)
        end,
        forget = function(_self: SessionMarks, userId: number)
            armed[userId] = nil
        end,
    }
    return marks
end

return SessionMarksModule
