--!strict
local StreakClock = require("../../../src/shared/features/timerewards/StreakClock")
local harness = require("../../harness")

local DAY = 86400
local HOUR = 3600

local function streakOf(decision: StreakClock.Decision): number
    if decision.ok then
        return decision.streak
    end
    return -1
end

local function reasonOf(decision: StreakClock.Decision): string
    if decision.ok then
        return "ok"
    end
    return decision.reason
end

return function(suite: harness.Harness)
    suite:test("dayIndex counts UTC days from 1", function()
        harness.equal(StreakClock.dayIndex(0), 1)
        harness.equal(StreakClock.dayIndex(DAY - 1), 1)
        harness.equal(StreakClock.dayIndex(DAY), 2)
    end)

    suite:test("the first claim starts a streak of 1", function()
        local decision = StreakClock.evaluate({ lastDay = 0, streak = 0 }, 10 * DAY + 5, 0)
        harness.equal(streakOf(decision), 1)
    end)

    suite:test("a second claim on the same day is already claimed", function()
        local state = { lastDay = 11, streak = 2 }
        harness.equal(reasonOf(StreakClock.evaluate(state, 10 * DAY + 9000, 0)), "already_claimed")
    end)

    suite:test("the next day continues the streak", function()
        local state = { lastDay = 11, streak = 2 }
        harness.equal(streakOf(StreakClock.evaluate(state, 11 * DAY + 1, 0)), 3)
    end)

    suite:test("a missed day resets the streak with no grace", function()
        local state = { lastDay = 11, streak = 4 }
        local decision = StreakClock.evaluate(state, 12 * DAY + 1, 0)
        harness.equal(streakOf(decision), 1)
        harness.isTrue(decision.ok and decision.reset, "flagged as a reset")
    end)

    suite:test("the grace window keeps the streak alive after a missed day", function()
        local state = { lastDay = 11, streak = 4 }
        -- Day 12 ends at 12 * DAY; 6 h of grace reach 12 * DAY + 6 h.
        harness.equal(streakOf(StreakClock.evaluate(state, 12 * DAY + 5 * HOUR, 6)), 5)
        harness.equal(streakOf(StreakClock.evaluate(state, 12 * DAY + 6 * HOUR, 6)), 1)
    end)

    suite:test("a clock that went backwards is refused", function()
        local state = { lastDay = 11, streak = 4 }
        harness.equal(reasonOf(StreakClock.evaluate(state, 5 * DAY, 6)), "clock_regressed")
    end)

    suite:test("evaluate never mutates the state", function()
        local state = { lastDay = 11, streak = 4 }
        StreakClock.evaluate(state, 11 * DAY + 1, 0)
        harness.equal(state.streak, 4)
        harness.equal(state.lastDay, 11)
    end)
end
