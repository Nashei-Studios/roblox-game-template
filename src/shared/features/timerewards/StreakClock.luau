--!strict
--[[
    Pure daily-streak arithmetic on the SERVER clock (issue #27). No engine, no os calls: the
    caller passes `now` (Unix seconds, UTC).

    A "day" is a UTC calendar day numbered from 1 (`dayIndex`). `lastDay` 0 means never claimed.
    - Same day as the last claim: already claimed (idempotent per period).
    - Next day: the streak continues.
    - Later: the streak continues only while `now` is inside the grace window that follows the end
      of the day after the last claim; past it, the streak restarts at 1.
    - A clock that went backwards (today before the last claim) is refused, never rewarded.
]]

export type State = { lastDay: number, streak: number }

export type Decision =
    { ok: true, streak: number, day: number, reset: boolean }
    | { ok: false, reason: "already_claimed" | "clock_regressed" }

local SECONDS_PER_DAY = 86400
local SECONDS_PER_HOUR = 3600

local StreakClock = {}

--- UTC day number of `now`, starting at 1.
function StreakClock.dayIndex(now: number): number
    return math.floor(now / SECONDS_PER_DAY) + 1
end

--- Decides a claim at `now`. Does not mutate `state`.
function StreakClock.evaluate(state: State, now: number, graceHours: number): Decision
    local today = StreakClock.dayIndex(now)
    if state.lastDay == 0 then
        return { ok = true, streak = 1, day = today, reset = false }
    end
    if today < state.lastDay then
        return { ok = false, reason = "clock_regressed" }
    end
    if today == state.lastDay then
        return { ok = false, reason = "already_claimed" }
    end
    -- Day D ends at D * 86400, so the day after the last claim ends at (lastDay + 1) * 86400.
    local aliveUntil = (state.lastDay + 1) * SECONDS_PER_DAY + graceHours * SECONDS_PER_HOUR
    if now < aliveUntil then
        return { ok = true, streak = state.streak + 1, day = today, reset = false }
    end
    return { ok = true, streak = 1, day = today, reset = true }
end

return StreakClock
