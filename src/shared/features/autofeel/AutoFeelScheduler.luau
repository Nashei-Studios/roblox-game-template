--!strict
--[[
    The clock of the auto visuals (ADR 0058). It never pays anything and never invents a value: the
    server pays the drill, the game feeds the scheduler the deltas it read from server snapshots
    (`noteDelta`) and asks every frame what to show (`step`). It decides four things: one swing every
    `cadenceSeconds` whatever the rate, one aggregated popup per window, manual input winning for
    `overrideSeconds`, and pausing while the player moves, has a menu open or stands too far from
    the rock. While paused the pending delta is dropped (the HUD counter still shows the truth).
    Pure: time comes in as an argument. Loads under Lune.
]]

local AutoFeel = require("./AutoFeel")

export type PauseReason = "noAuto" | "manual" | "moving" | "menu" | "far"

export type Context = {
    -- Paid swings per second as the snapshot says (0 = no drill).
    rate: number,
    moving: boolean,
    menuOpen: boolean,
    -- Studs from the player to the rock.
    distance: number,
}

export type Tick = {
    active: boolean,
    paused: PauseReason?,
    -- Play one auto swing now.
    swing: boolean,
    -- Show one aggregated "+N" popup of this amount now.
    popup: number?,
}

export type Scheduler = {
    -- A manual tap or hold swing happened: the manual feel takes over.
    noteManual: (self: Scheduler, now: number) -> (),
    -- Value the server paid since the last snapshot (from the snapshot, never guessed).
    noteDelta: (self: Scheduler, amount: number) -> (),
    step: (self: Scheduler, now: number, context: Context) -> Tick,
}

local AutoFeelScheduler = {}

--- Why the auto visuals are paused, or nil when they run. First match wins, in this order.
function AutoFeelScheduler.pauseReason(
    config: AutoFeel.AutoFeelConfig,
    context: Context,
    secondsSinceManual: number
): PauseReason?
    if context.rate <= 0 then
        return "noAuto"
    elseif secondsSinceManual < config.overrideSeconds then
        return "manual"
    elseif context.menuOpen then
        return "menu"
    elseif context.moving then
        return "moving"
    elseif context.distance > config.radiusStuds then
        return "far"
    end
    return nil
end

function AutoFeelScheduler.new(config: AutoFeel.AutoFeelConfig): Scheduler
    local lastManual = -math.huge
    local lastSwing = -math.huge
    local lastPopup = -math.huge
    local pending = 0
    local wasActive = false

    local scheduler: Scheduler = {
        noteManual = function(_self: Scheduler, now: number)
            lastManual = now
            -- The manual swing just played: the first auto swing waits a full cadence.
            lastSwing = now
            pending = 0
        end,
        noteDelta = function(_self: Scheduler, amount: number)
            -- Paid while the visuals are paused: nothing to show, the HUD counter has it.
            if wasActive and amount > 0 and amount == amount and amount ~= math.huge then
                pending += amount
            end
        end,
        step = function(_self: Scheduler, now: number, context: Context): Tick
            local reason: PauseReason? =
                AutoFeelScheduler.pauseReason(config, context, now - lastManual)
            if reason ~= nil then
                pending = 0
                wasActive = false
                local paused: Tick = { active = false, paused = reason, swing = false, popup = nil }
                return paused
            end
            if not wasActive then
                -- Resuming: the first popup waits a full window so it sums real time at the rock.
                wasActive = true
                lastPopup = now
            end
            local swing = now - lastSwing >= config.cadenceSeconds
            if swing then
                lastSwing = now
            end
            local popup: number? = nil
            if pending > 0 and now - lastPopup >= config.aggregateWindowSeconds then
                popup = pending
                pending = 0
                lastPopup = now
            end
            return { active = true, paused = nil, swing = swing, popup = popup }
        end,
    }
    return scheduler
end

return AutoFeelScheduler
