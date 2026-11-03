--!strict
--[[
    Orchestrates the Key sprint remotes (ADR 0020). Pure: every engine effect (walk speed,
    teleport, sending a remote, opening a purchase prompt) and every lookup (player data, rate
    limits) is injected, so the whole loop runs under Lune. `Main.server` is the only place that
    wires it to Zap, Humanoids and MarketplaceService.

    Rule: a handler receives what the client SENT (unknown) and returns a typed outcome. Nothing
    here uses a speed, price, reward or stage number that came from the client without checking.
]]

local ChargeMeter = require("./ChargeMeter")
local Funnel = require("./Funnel")
local KeySprintRules = require("./KeySprintRules")
local Progression = require("./Progression")
local StageRuns = require("./StageRuns")

export type Data = Progression.Target

export type Effects = {
    setWalkSpeed: (userId: number, speed: number) -> (),
    sendMultiplier: (userId: number, multiplier: number, cap: number) -> (),
    sendProgress: (userId: number, highestStage: number, cap: number) -> (),
    sendCoins: (userId: number, coins: number) -> (),
    teleportToStage: (userId: number, stage: number) -> (),
    -- Opens the Skip stage purchase prompt; false when it could not.
    promptSkip: (userId: number) -> boolean,
}

export type Deps = {
    charge: ChargeMeter.ChargeMeter,
    runs: StageRuns.StageRuns,
    funnel: Funnel.Funnel,
    -- The loaded player data, or nil when it is not loaded.
    dataFor: (userId: number) -> Data?,
    -- Rate limit per remote name ("PressBatch", "Finish", "BuyCap", "SkipStage").
    allow: (remote: string, userId: number) -> boolean,
    effects: Effects,
}

export type Outcome = { ok: true } | { ok: false, reason: string }

export type KeySprintController = {
    onJoin: (self: KeySprintController, userId: number, sessionIndex: number) -> boolean,
    onRespawn: (self: KeySprintController, userId: number) -> boolean,
    onPressBatch: (self: KeySprintController, userId: number, presses: unknown) -> Outcome,
    onFinish: (self: KeySprintController, userId: number, stage: unknown) -> Outcome,
    onBuyCap: (self: KeySprintController, userId: number) -> Outcome,
    onSkipStageRequest: (self: KeySprintController, userId: number) -> Outcome,
    -- The saved progress changed outside a remote (a Skip stage grant): resync and move on.
    onProgressGranted: (self: KeySprintController, userId: number) -> (),
    setFasterCharge: (self: KeySprintController, userId: number, enabled: boolean) -> (),
    -- Call a few times per second: reports multiplier decay and keeps the walk speed in step.
    tick: (self: KeySprintController, userIds: { number }) -> (),
    onLeave: (self: KeySprintController, userId: number) -> (),
}

local ACCEPTED: Outcome = { ok = true }

-- A multiplier change smaller than this is not worth a remote message.
local MIN_REPORTED_CHANGE = 0.05

local KeySprintControllerModule = {}

local function refused(reason: string): Outcome
    return { ok = false, reason = reason }
end

function KeySprintControllerModule.new(deps: Deps): KeySprintController
    local effects = deps.effects
    -- Last multiplier sent to each client.
    local lastSent: { [number]: number } = {}

    local function applyMultiplier(userId: number, multiplier: number, cap: number)
        lastSent[userId] = multiplier
        effects.setWalkSpeed(userId, KeySprintRules.BASE_WALK_SPEED * multiplier)
        effects.sendMultiplier(userId, multiplier, cap)
    end

    -- Back to base speed at the start gate of `stage`.
    local function placeAtStage(userId: number, stage: number, cap: number)
        deps.charge:reset(userId)
        lastSent[userId] = 1
        effects.sendMultiplier(userId, 1, cap)
        effects.teleportToStage(userId, stage)
        effects.setWalkSpeed(userId, KeySprintRules.BASE_WALK_SPEED)
    end

    local controller: KeySprintController = {
        onJoin = function(
            _self: KeySprintController,
            userId: number,
            sessionIndex: number
        ): boolean
            local data = deps.dataFor(userId)
            if data == nil then
                return false
            end
            deps.funnel:onJoin(userId, sessionIndex, data.highestStage)
            local stage = Progression.startStage(data)
            deps.runs:begin(userId, stage)
            effects.sendCoins(userId, data.coins)
            effects.sendProgress(userId, data.highestStage, data.multiplierCap)
            placeAtStage(userId, stage, data.multiplierCap)
            return true
        end,
        onRespawn = function(_self: KeySprintController, userId: number): boolean
            local data = deps.dataFor(userId)
            if data == nil then
                return false
            end
            -- The checkpoint is the start gate of the stage being run. The run clock keeps
            -- going: a death never makes the finish check stricter or looser.
            local stage = deps.runs:activeStage(userId) or Progression.startStage(data)
            placeAtStage(userId, stage, data.multiplierCap)
            return true
        end,
        onPressBatch = function(
            _self: KeySprintController,
            userId: number,
            presses: unknown
        ): Outcome
            if not deps.allow("PressBatch", userId) then
                return refused("rate_limited")
            end
            local data = deps.dataFor(userId)
            if data == nil then
                return refused("no_data")
            end
            local pressed = deps.charge:press(userId, presses, data.multiplierCap)
            if not pressed.ok then
                return refused(pressed.reason)
            end
            deps.funnel:onPressAccepted(userId)
            applyMultiplier(userId, pressed.multiplier, data.multiplierCap)
            return ACCEPTED
        end,
        onFinish = function(_self: KeySprintController, userId: number, stage: unknown): Outcome
            if not deps.allow("Finish", userId) then
                return refused("rate_limited")
            end
            local data = deps.dataFor(userId)
            if data == nil then
                return refused("no_data")
            end
            local finished = deps.runs:finish(userId, stage, data.multiplierCap, data.highestStage)
            if not finished.ok then
                return refused(finished.reason)
            end
            local outcome = Progression.applyFinish(data, finished.stage)
            deps.funnel:onFinishAccepted(userId, finished.stage, outcome.firstClear)
            local nextStage = Progression.startStage(data)
            deps.runs:begin(userId, nextStage)
            effects.sendCoins(userId, data.coins)
            effects.sendProgress(userId, data.highestStage, data.multiplierCap)
            placeAtStage(userId, nextStage, data.multiplierCap)
            return ACCEPTED
        end,
        onBuyCap = function(_self: KeySprintController, userId: number): Outcome
            if not deps.allow("BuyCap", userId) then
                return refused("rate_limited")
            end
            local data = deps.dataFor(userId)
            if data == nil then
                return refused("no_data")
            end
            local bought = Progression.buyCap(data)
            if not bought.ok then
                return refused(bought.reason)
            end
            effects.sendCoins(userId, data.coins)
            effects.sendProgress(userId, data.highestStage, data.multiplierCap)
            return ACCEPTED
        end,
        onSkipStageRequest = function(_self: KeySprintController, userId: number): Outcome
            if not deps.allow("SkipStage", userId) then
                return refused("rate_limited")
            end
            local data = deps.dataFor(userId)
            if data == nil then
                return refused("no_data")
            end
            if Progression.isComplete(data) then
                return refused("complete")
            end
            if not effects.promptSkip(userId) then
                return refused("prompt_failed")
            end
            return ACCEPTED
        end,
        onProgressGranted = function(_self: KeySprintController, userId: number)
            local data = deps.dataFor(userId)
            if data == nil then
                return
            end
            local stage = Progression.startStage(data)
            deps.runs:begin(userId, stage)
            effects.sendProgress(userId, data.highestStage, data.multiplierCap)
            placeAtStage(userId, stage, data.multiplierCap)
        end,
        setFasterCharge = function(_self: KeySprintController, userId: number, enabled: boolean)
            deps.charge:setFasterCharge(userId, enabled)
        end,
        tick = function(_self: KeySprintController, userIds: { number })
            for _, userId in userIds do
                local data = deps.dataFor(userId)
                if data == nil then
                    continue
                end
                local multiplier = deps.charge:multiplier(userId, data.multiplierCap)
                local previous = lastSent[userId]
                if previous == nil or math.abs(multiplier - previous) >= MIN_REPORTED_CHANGE then
                    applyMultiplier(userId, multiplier, data.multiplierCap)
                end
            end
        end,
        onLeave = function(_self: KeySprintController, userId: number)
            lastSent[userId] = nil
            deps.charge:forget(userId)
            deps.runs:forget(userId)
            deps.funnel:forget(userId)
        end,
    }
    return controller
end

return KeySprintControllerModule
