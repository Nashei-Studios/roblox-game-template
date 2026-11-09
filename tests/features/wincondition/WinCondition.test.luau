--!strict
local WinCondition = require("../../../src/shared/features/wincondition/WinCondition")
local harness = require("../../harness")

local function filled(): WinCondition.WinConditionConfig
    return {
        hypothesis = "Many players hit one giant rock; the clip shows it exploding.",
        hookSentence = "Everyone hits one giant rock",
        shareableMomentIds = { "big_break" },
        borrowedChannel = "Moments feed",
        solo = false,
        funnyElement = "Ragdoll players fly away",
        measurementPlan = {
            { name = "play-through rate", source = "Creator Analytics" },
            { name = "D1", source = "Creator Analytics" },
        },
        targetOwner = "owner",
        targetDate = "2026-12-01",
    }
end

local function has(list: { string }, needle: string): boolean
    return string.find(table.concat(list, "|"), needle, 1, true) ~= nil
end

return function(suite: harness.Harness)
    suite:test("a complete declaration has no problems and nothing missing", function()
        local report = WinCondition.validate(filled(), { big_break = true })
        harness.equal(#report.problems, 0)
        harness.equal(#report.missing, 0)
    end)

    suite:test("the empty declaration lists every field as missing and no problem", function()
        local report = WinCondition.validate(WinCondition.empty(), nil)
        harness.equal(#report.problems, 0)
        harness.equal(#report.missing, 8)
        for _, field in
            {
                "hypothesis",
                "hookSentence",
                "shareableMomentIds",
                "borrowedChannel",
                "funnyElement",
                "measurementPlan",
                "targetOwner",
                "targetDate",
            }
        do
            harness.isTrue(has(report.missing, field), field)
        end
    end)

    suite:test("a solo game may declare no moment id", function()
        local solo = filled()
        solo.solo = true
        solo.shareableMomentIds = {}
        harness.equal(#WinCondition.validate(solo, nil).missing, 0)
    end)

    suite:test("a hook over nine words is a problem, nine words pass", function()
        local long = filled()
        long.hookSentence = "one two three four five six seven eight nine ten"
        harness.isTrue(has(WinCondition.validate(long, nil).problems, "10 words"))
        long.hookSentence = "one two three four five six seven eight nine"
        harness.equal(#WinCondition.validate(long, nil).problems, 0)
    end)

    suite:test("moment ids: empty, repeated and unknown are problems", function()
        local bad = filled()
        bad.shareableMomentIds = { "big_break", "big_break", "", "ghost" }
        local problems = WinCondition.validate(bad, { big_break = true }).problems
        harness.isTrue(has(problems, "repeats"))
        harness.isTrue(has(problems, "empty id"))
        harness.isTrue(has(problems, `"ghost" is not a declared clip moment`))
        harness.equal(
            #WinCondition.validate(bad, nil).problems,
            2,
            "without a known set only shape is checked"
        )
    end)

    suite:test("metrics need a name and a source and must not repeat", function()
        local bad = filled()
        bad.measurementPlan = {
            { name = "D1", source = "" },
            { name = "PTR", source = "Creator Analytics" },
            { name = "PTR", source = "Creator Analytics" },
        }
        local problems = WinCondition.validate(bad, nil).problems
        harness.isTrue(has(problems, "name and a source"))
        harness.isTrue(has(problems, `repeats "PTR"`))
    end)

    suite:test("the target date must be an ISO date; blank text counts as missing", function()
        local bad = filled()
        bad.targetDate = "1 December"
        bad.hypothesis = "   "
        local report = WinCondition.validate(bad, nil)
        harness.isTrue(has(report.problems, "ISO date"))
        harness.isTrue(has(report.missing, "hypothesis"))
    end)
end
