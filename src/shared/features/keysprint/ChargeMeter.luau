--!strict
--[[
    Server-side multiplier charge (ADR 0020). Pure: the clock and the press limiter are
    injected, so it loads under Lune and tests control time.

    The client sends a COUNT of presses; this module decides what that is worth. A batch is
    validated first (so garbage costs nothing), then it spends one limiter token per press
    (the server rate bounds the charge, never the batch size the client claims), then it adds
    charge, clipped so that multiplier = min(cap, 1 + charge) never passes the player's cap.
    Charge decays while idle. The Faster charge pass multiplies the charge per press; it does
    not touch the cap.
]]

local KeySprintRules = require("./KeySprintRules")
local Validation = require("../../net/Validation")

export type PressLimiter = {
    allow: (self: PressLimiter, userId: number, cost: number?) -> boolean,
}

export type Deps = {
    -- Seconds, monotonic (os.clock on the server).
    clock: () -> number,
    -- One token per press: burst KeySprintRules.PRESS_BURST, sustained MAX_PRESSES_PER_SECOND.
    pressLimiter: PressLimiter,
}

export type Reason = "rate_limited" | Validation.ValidationError

export type PressResult = { ok: true, multiplier: number } | { ok: false, reason: Reason }

export type ChargeMeter = {
    -- Accepts a batch of presses (`presses` is what the client sent, unvalidated) and returns
    -- the player's multiplier after it.
    press: (self: ChargeMeter, userId: number, presses: unknown, cap: number) -> PressResult,
    -- Current multiplier after decay, clipped to `cap`. 1 for a player who never pressed.
    multiplier: (self: ChargeMeter, userId: number, cap: number) -> number,
    setFasterCharge: (self: ChargeMeter, userId: number, enabled: boolean) -> (),
    -- Drops the charge (after a stage or a respawn); keeps the pass.
    reset: (self: ChargeMeter, userId: number) -> (),
    forget: (self: ChargeMeter, userId: number) -> (),
}

type State = { charge: number, updatedAt: number, faster: boolean }

local ChargeMeterModule = {}

function ChargeMeterModule.new(deps: Deps): ChargeMeter
    local states: { [number]: State } = {}

    local function stateFor(userId: number): State
        local state = states[userId]
        if state == nil then
            state = { charge = 0, updatedAt = deps.clock(), faster = false }
            states[userId] = state
        end
        return state
    end

    -- Applies the idle decay up to now.
    local function settle(state: State)
        local now = deps.clock()
        local elapsed = math.max(0, now - state.updatedAt)
        state.charge = math.max(0, state.charge - elapsed * KeySprintRules.DECAY_PER_SECOND)
        state.updatedAt = now
    end

    local meter: ChargeMeter = {
        press = function(
            _self: ChargeMeter,
            userId: number,
            presses: unknown,
            cap: number
        ): PressResult
            local checked =
                Validation.integerInRange(presses, 1, KeySprintRules.MAX_PRESSES_PER_BATCH)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            if not deps.pressLimiter:allow(userId, checked.value) then
                return { ok = false, reason = "rate_limited" }
            end
            local state = stateFor(userId)
            settle(state)
            local perPress = KeySprintRules.CHARGE_PER_PRESS
            if state.faster then
                perPress *= KeySprintRules.FASTER_CHARGE_FACTOR
            end
            state.charge = math.min(math.max(cap - 1, 0), state.charge + checked.value * perPress)
            return { ok = true, multiplier = math.min(cap, 1 + state.charge) }
        end,
        multiplier = function(_self: ChargeMeter, userId: number, cap: number): number
            local state = states[userId]
            if state == nil then
                return 1
            end
            settle(state)
            return math.min(cap, 1 + state.charge)
        end,
        setFasterCharge = function(_self: ChargeMeter, userId: number, enabled: boolean)
            stateFor(userId).faster = enabled
        end,
        reset = function(_self: ChargeMeter, userId: number)
            local state = states[userId]
            if state ~= nil then
                state.charge = 0
                state.updatedAt = deps.clock()
            end
        end,
        forget = function(_self: ChargeMeter, userId: number)
            states[userId] = nil
        end,
    }
    return meter
end

return ChargeMeterModule
