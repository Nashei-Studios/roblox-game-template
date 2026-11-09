--!strict
--[[
    A server-authoritative shared objective (ADR 0049): a goal everybody in the server pushes at
    once. It opens on a timer, a shared bar fills with the units players contribute, and it ends
    in a completion (the drop) or a failure. Pure state machine with the clock injected, so Lune
    tests its whole life. The server wiring feeds `contribute` with units the game already
    accepted (a client has no path of its own) and calls `tick` about once a second.

    Beats (what a presenter, a music mood resolver or a camera reads, one string):
      idle       waiting for the next objective
      buildup    the objective is open
      drop       it just completed (held for `resultHoldSeconds`)
      fail       it just ran out of time (held for `resultHoldSeconds`)
    The beat is derived from the state, never stored by a presenter.
]]

local ObjectiveConfig = require("./ObjectiveConfig")

export type Phase = "waiting" | "open"
export type Beat = "idle" | "buildup" | "drop" | "fail"

export type Completion = {
    userId: number,
    -- 1 = most units; ties are broken by the lower user id so the order is stable.
    rank: number,
    units: number,
    -- True for the first `topCount` ranks.
    top: boolean,
}

export type Event =
    { kind: "opened", target: number, closesAt: number }
    | { kind: "completed", completions: { Completion } }
    | { kind: "failed" }

export type View = {
    phase: Phase,
    beat: Beat,
    -- Units in the bar and units that fill it (0 while waiting).
    progress: number,
    target: number,
    -- Clock seconds: when the open objective closes, or when the next one opens.
    closesAt: number,
    nextAt: number,
    -- Objectives completed since the server started; a client reacts to every change.
    completed: number,
}

type Bucket = { tokens: number, last: number }

export type SharedObjective = {
    -- Adds units of a player; returns how many counted (the rate cap drops the rest). Nothing
    -- counts while the objective is waiting.
    contribute: (self: SharedObjective, userId: number, units: number, now: number) -> number,
    -- Advances the clock. `present` are the user ids in the server now. Returns what happened.
    tick: (self: SharedObjective, now: number, present: { number }) -> { Event },
    view: (self: SharedObjective, now: number) -> View,
}

local SharedObjectiveModule = {}

--- Units the bar asks for with `players` in the server (never fewer than one player's worth).
function SharedObjectiveModule.targetFor(
    config: ObjectiveConfig.ObjectiveConfig,
    players: number
): number
    return config.unitsPerPlayer * math.max(1, players)
end

function SharedObjectiveModule.new(
    config: ObjectiveConfig.ObjectiveConfig,
    startedAt: number
): SharedObjective
    local phase: Phase = "waiting"
    local nextAt = startedAt + config.intervalSeconds
    local firstSeen = false
    local closesAt = 0
    local target = 0
    local progress = 0
    local completed = 0
    local resolvedAt = -math.huge
    local lastResult: Beat = "idle"
    local contributions: { [number]: number } = {}
    local buckets: { [number]: Bucket } = {}

    local function reset()
        progress = 0
        target = 0
        contributions = {}
        buckets = {}
    end

    local function ranking(): { Completion }
        local eligible: { { userId: number, units: number } } = {}
        for userId, units in contributions do
            if units >= math.max(1, config.minContribution) then
                table.insert(eligible, { userId = userId, units = units })
            end
        end
        table.sort(eligible, function(a, b)
            if a.units ~= b.units then
                return a.units > b.units
            end
            return a.userId < b.userId
        end)
        local result: { Completion } = {}
        for rank, entry in eligible do
            table.insert(result, {
                userId = entry.userId,
                rank = rank,
                units = entry.units,
                top = rank <= config.topCount,
            })
        end
        return result
    end

    local objective: SharedObjective = {
        contribute = function(
            _self: SharedObjective,
            userId: number,
            units: number,
            now: number
        ): number
            if phase ~= "open" or not (units >= 1) or now >= closesAt then
                return 0
            end
            local bucket = buckets[userId]
            if bucket == nil then
                bucket = { tokens = config.maxUnitsPerSecond, last = now }
                buckets[userId] = bucket
            end
            local refilled = bucket.tokens + (now - bucket.last) * config.maxUnitsPerSecond
            bucket.tokens = math.min(config.maxUnitsPerSecond, refilled)
            bucket.last = now
            local counted = math.min(math.floor(units), math.floor(bucket.tokens))
            bucket.tokens -= counted
            if counted > 0 then
                progress += counted
                contributions[userId] = (contributions[userId] or 0) + counted
            end
            return counted
        end,
        tick = function(_self: SharedObjective, now: number, present: { number }): { Event }
            local events: { Event } = {}
            if phase == "waiting" then
                if not firstSeen and #present > 0 then
                    firstSeen = true
                    nextAt = math.min(nextAt, now + config.firstOpenSeconds)
                end
                -- An empty server keeps it closed; it opens on the first tick with someone in.
                if now >= nextAt and #present > 0 then
                    phase = "open"
                    closesAt = now + config.durationSeconds
                    target = SharedObjectiveModule.targetFor(config, #present)
                    table.insert(events, { kind = "opened", target = target, closesAt = closesAt })
                end
                return events
            end
            -- Open. Players who arrive raise the target; it never drops, so leaving cannot cheat.
            target = math.max(target, SharedObjectiveModule.targetFor(config, #present))
            if progress >= target then
                completed += 1
                lastResult = "drop"
                table.insert(events, { kind = "completed", completions = ranking() })
            elseif now >= closesAt then
                lastResult = "fail"
                table.insert(events, { kind = "failed" })
            else
                return events
            end
            phase = "waiting"
            resolvedAt = now
            nextAt = now + config.intervalSeconds
            reset()
            return events
        end,
        view = function(_self: SharedObjective, now: number): View
            local beat: Beat = "idle"
            if phase == "open" then
                beat = "buildup"
            elseif now - resolvedAt < config.resultHoldSeconds then
                beat = lastResult
            end
            return {
                phase = phase,
                beat = beat,
                progress = progress,
                target = target,
                closesAt = if phase == "open" then closesAt else 0,
                nextAt = if phase == "waiting" then nextAt else 0,
                completed = completed,
            }
        end,
    }
    return objective
end

return SharedObjectiveModule
