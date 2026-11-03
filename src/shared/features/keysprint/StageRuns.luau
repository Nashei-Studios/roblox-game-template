--!strict
--[[
    Server-side validation of stage arrival (ADR 0020). Pure: the clock and the stage lengths
    are injected. The server starts a run when it puts the player at a stage's start gate; a
    `Finish` is accepted only for that stage, only when the stage is unlocked and only after the
    minimum plausible time: pathLength / (BASE_WALK_SPEED x cap) x PLAUSIBLE_TIME_FACTOR. The
    bound uses the player's CAP, not the live multiplier, so it is loose on purpose: it stops
    teleports and instant finishes, not a player who is fast for real.
    An accepted finish ends the run (it cannot be repeated); a rejected one keeps it.
]]

local KeySprintRules = require("./KeySprintRules")
local Validation = require("../../net/Validation")

export type Deps = {
    clock: () -> number,
    -- Studs from the start gate to the finish line of a stage.
    pathLength: (stage: number) -> number,
}

export type Reason =
    "no_active_run"
    | "wrong_stage"
    | "locked"
    | "too_fast"
    | Validation.ValidationError

export type FinishResult = { ok: true, stage: number } | { ok: false, reason: Reason }

export type StageRuns = {
    -- Starts (or restarts) the run of `stage` for the player now.
    begin: (self: StageRuns, userId: number, stage: number) -> (),
    -- `stage` is what the client sent (unvalidated); `highestStage` comes from the saved data.
    finish: (
        self: StageRuns,
        userId: number,
        stage: unknown,
        cap: number,
        highestStage: number
    ) -> FinishResult,
    minimumSeconds: (self: StageRuns, stage: number, cap: number) -> number,
    activeStage: (self: StageRuns, userId: number) -> number?,
    forget: (self: StageRuns, userId: number) -> (),
}

type Run = { stage: number, startedAt: number }

local StageRunsModule = {}

function StageRunsModule.new(deps: Deps): StageRuns
    local runs: { [number]: Run } = {}

    local service: StageRuns
    service = {
        begin = function(_self: StageRuns, userId: number, stage: number)
            runs[userId] = { stage = stage, startedAt = deps.clock() }
        end,
        finish = function(
            self: StageRuns,
            userId: number,
            stage: unknown,
            cap: number,
            highestStage: number
        ): FinishResult
            local checked = Validation.integerInRange(stage, 1, KeySprintRules.STAGE_COUNT)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            local run = runs[userId]
            if run == nil then
                return { ok = false, reason = "no_active_run" }
            end
            if run.stage ~= checked.value then
                return { ok = false, reason = "wrong_stage" }
            end
            if checked.value > highestStage + 1 then
                return { ok = false, reason = "locked" }
            end
            local elapsed = deps.clock() - run.startedAt
            if elapsed < self:minimumSeconds(checked.value, cap) then
                return { ok = false, reason = "too_fast" }
            end
            runs[userId] = nil
            return { ok = true, stage = checked.value }
        end,
        minimumSeconds = function(_self: StageRuns, stage: number, cap: number): number
            return deps.pathLength(stage)
                / (KeySprintRules.BASE_WALK_SPEED * cap)
                * KeySprintRules.PLAUSIBLE_TIME_FACTOR
        end,
        activeStage = function(_self: StageRuns, userId: number): number?
            local run = runs[userId]
            if run == nil then
                return nil
            end
            return run.stage
        end,
        forget = function(_self: StageRuns, userId: number)
            runs[userId] = nil
        end,
    }
    return service
end

return StageRunsModule
