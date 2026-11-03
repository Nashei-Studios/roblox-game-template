--!strict
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local StageLayout = require("../../../src/shared/features/keysprint/StageLayout")
local StageSpecs = require("../../../src/shared/features/keysprint/StageSpecs")
local harness = require("../../harness")

local function kinds(layout: StageLayout.Layout): { string }
    local out: { string } = {}
    for _, part in layout.parts do
        table.insert(out, part.kind)
    end
    return out
end

return function(suite: harness.Harness)
    suite:test("there are exactly STAGE_COUNT stage specs and rewards", function()
        harness.equal(#StageSpecs.all, KeySprintRules.STAGE_COUNT, "stage count")
        harness.equal(#KeySprintRules.STAGE_REWARDS, KeySprintRules.STAGE_COUNT, "rewards")
    end)

    suite:test("the first stage is short with one gap and one moving platform", function()
        local spec = StageSpecs.all[1]
        local gaps, movers = 0, 0
        for _, segment in spec.segments do
            if segment.kind == "gap" then
                gaps += 1
            elseif segment.kind == "mover" then
                movers += 1
            end
        end
        harness.equal(gaps, 1, "gaps")
        harness.equal(movers, 1, "movers")
    end)

    suite:test("every spec is valid and every gap is jumpable at base speed", function()
        for index, spec in StageSpecs.all do
            local problems = StageSpecs.validate(spec)
            harness.equal(#problems, 0, `stage {index}: {table.concat(problems, "; ")}`)
        end
    end)

    suite:test("validate reports a wide gap and a stage that starts with a gap", function()
        local problems = StageSpecs.validate({
            segments = {
                { kind = "gap", length = 4 },
                { kind = "platform", length = 10 },
                { kind = "gap", length = StageSpecs.MAX_GAP + 1 },
                { kind = "platform", length = 10 },
            },
        })
        harness.equal(#problems, 2, "two problems")
    end)

    suite:test("validate reports a stage that ends with a gap and bad lengths", function()
        harness.equal(#StageSpecs.validate({ segments = {} }), 1, "empty")
        harness.equal(#StageSpecs.validate({
            segments = {
                { kind = "platform", length = 10 },
                { kind = "gap", length = 4 },
            },
        }), 1, "ends with a gap")
        harness.isTrue(#StageSpecs.validate({
            segments = {
                { kind = "platform", length = 0 },
                { kind = "mover", length = 10, travel = 0, period = 2 },
            },
        }) >= 2, "bad lengths")
    end)

    suite:test("the layout lists start first and finish last", function()
        local layout = StageLayout.compute(StageSpecs.all[1])
        local list = kinds(layout)
        harness.equal(list[1], "start", "first part")
        harness.equal(list[#list], "finish", "last part")
    end)

    suite:test("path length is the sum of segment lengths", function()
        for _, spec in StageSpecs.all do
            local total = 0
            for _, segment in spec.segments do
                total += segment.length
            end
            harness.equal(StageLayout.compute(spec).pathLength, total, "path length")
        end
    end)

    suite:test("platforms follow each other along Z without overlapping", function()
        for _, spec in StageSpecs.all do
            local layout = StageLayout.compute(spec)
            local previousEnd = -math.huge
            for _, part in layout.parts do
                if part.kind == "platform" or part.kind == "mover" then
                    local front = part.z - part.sizeZ / 2
                    harness.isTrue(front >= previousEnd - 1e-9, "no overlap")
                    previousEnd = part.z + part.sizeZ / 2
                end
            end
        end
    end)

    suite:test("a mover carries its travel and period; other parts do not", function()
        local layout = StageLayout.compute(StageSpecs.all[1])
        local movers = 0
        for _, part in layout.parts do
            if part.kind == "mover" then
                movers += 1
                harness.isTrue((part.travel or 0) > 0 and (part.period or 0) > 0, "mover data")
            else
                harness.isTrue(part.travel == nil, "static part")
            end
        end
        harness.equal(movers, 1, "one mover")
    end)

    suite:test("the spawn is above the start gate and the finish sits at the path end", function()
        local layout = StageLayout.compute(StageSpecs.all[2])
        harness.isTrue(layout.spawn.y > 0, "spawn above the deck")
        harness.equal(layout.spawn.z, 0, "spawn at the start gate")
        harness.equal(layout.finish.z, layout.pathLength, "finish at the end")
    end)

    suite:test("compute does not mutate the spec", function()
        local spec = StageSpecs.all[1]
        local before = #spec.segments
        StageLayout.compute(spec)
        harness.equal(#spec.segments, before, "segments")
    end)
end
