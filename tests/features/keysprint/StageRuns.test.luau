--!strict
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local StageRuns = require("../../../src/shared/features/keysprint/StageRuns")
local harness = require("../../harness")

-- Every stage is 200 studs long in these tests: at cap 5 the minimum is 200 / 80 x 0.9 = 2.25 s.
local function newRuns()
    local now = 0
    local runs = StageRuns.new({
        clock = function(): number
            return now
        end,
        pathLength = function(_stage: number): number
            return 200
        end,
    })
    local function advance(seconds: number)
        now += seconds
    end
    return runs, advance
end

local function reasonOf(result: StageRuns.FinishResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

local MIN_AT_CAP_5 = 200
    / (KeySprintRules.BASE_WALK_SPEED * 5)
    * KeySprintRules.PLAUSIBLE_TIME_FACTOR

return function(suite: harness.Harness)
    suite:test("minimumSeconds is path length over the fastest speed times the factor", function()
        local runs = newRuns()
        harness.isTrue(math.abs(runs:minimumSeconds(1, 5) - MIN_AT_CAP_5) < 1e-9, "cap 5")
        harness.isTrue(runs:minimumSeconds(1, 10) < runs:minimumSeconds(1, 5), "higher cap")
    end)

    suite:test("a finish with no active run is rejected", function()
        local runs = newRuns()
        harness.equal(reasonOf(runs:finish(1, 1, 5, 0)), "no_active_run")
    end)

    suite:test("a finish too soon after the run began is rejected as too fast", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(MIN_AT_CAP_5 - 0.1)
        harness.equal(reasonOf(runs:finish(1, 1, 5, 0)), "too_fast")
    end)

    suite:test("a finish after the minimum time is accepted for that stage", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(MIN_AT_CAP_5 + 0.1)
        local result = runs:finish(1, 1, 5, 0)
        harness.isTrue(result.ok, "accepted")
        if result.ok then
            harness.equal(result.stage, 1, "stage")
        end
    end)

    suite:test("the stage must be the active one", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(60)
        harness.equal(reasonOf(runs:finish(1, 2, 5, 1)), "wrong_stage")
    end)

    suite:test("a stage that is not unlocked yet is refused", function()
        local runs, advance = newRuns()
        runs:begin(1, 3)
        advance(60)
        harness.equal(reasonOf(runs:finish(1, 3, 5, 1)), "locked", "needs highestStage 2")
        harness.isTrue(runs:finish(1, 3, 5, 2).ok, "unlocked")
    end)

    suite:test("a replay of a cleared stage is accepted", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(60)
        harness.isTrue(runs:finish(1, 1, 5, 3).ok, "replay")
    end)

    suite:test("an accepted finish ends the run: the same finish cannot repeat", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(60)
        harness.isTrue(runs:finish(1, 1, 5, 0).ok, "first")
        harness.equal(reasonOf(runs:finish(1, 1, 5, 1)), "no_active_run", "second")
    end)

    suite:test("a rejected too-fast finish keeps the run alive", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(0.1)
        harness.equal(reasonOf(runs:finish(1, 1, 5, 0)), "too_fast", "early")
        advance(60)
        harness.isTrue(runs:finish(1, 1, 5, 0).ok, "later")
    end)

    suite:test("garbage stage values are rejected by validation", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(60)
        harness.equal(reasonOf(runs:finish(1, "1", 5, 0)), "not_a_number", "string")
        harness.equal(reasonOf(runs:finish(1, 0, 5, 0)), "out_of_range", "zero")
        harness.equal(reasonOf(runs:finish(1, 99, 5, 0)), "out_of_range", "too high")
        harness.equal(reasonOf(runs:finish(1, 1.5, 5, 0)), "not_an_integer", "fraction")
    end)

    suite:test("players have separate runs and forget removes one", function()
        local runs, advance = newRuns()
        runs:begin(1, 1)
        advance(60)
        harness.equal(reasonOf(runs:finish(2, 1, 5, 0)), "no_active_run", "other player")
        runs:forget(1)
        harness.equal(reasonOf(runs:finish(1, 1, 5, 0)), "no_active_run", "forgotten")
    end)

    suite:test("activeStage reports the run or nil", function()
        local runs = newRuns()
        harness.isTrue(runs:activeStage(1) == nil, "none")
        runs:begin(1, 2)
        harness.equal(runs:activeStage(1), 2, "active")
    end)
end
