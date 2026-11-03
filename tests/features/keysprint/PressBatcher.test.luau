--!strict
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local PressBatcher = require("../../../src/shared/features/keysprint/PressBatcher")
local harness = require("../../harness")

return function(suite: harness.Harness)
    suite:test("nothing to send before any press", function()
        local batcher = PressBatcher.new(0.25)
        harness.equal(batcher:flush(10), 0, "empty")
    end)

    suite:test("presses are held until the interval passes, then flushed once", function()
        local batcher = PressBatcher.new(0.25)
        batcher:press()
        batcher:press()
        harness.equal(batcher:flush(0), 0, "first flush only starts the window")
        batcher:press()
        harness.equal(batcher:flush(0.1), 0, "window not over")
        harness.equal(batcher:flush(0.3), 3, "all presses")
        harness.equal(batcher:flush(0.6), 0, "drained")
    end)

    suite:test("a flush never returns more than MAX_PRESSES_PER_BATCH; the rest waits", function()
        local batcher = PressBatcher.new(0.25)
        batcher:flush(0)
        for _ = 1, 30 do
            batcher:press()
        end
        harness.equal(batcher:flush(1), KeySprintRules.MAX_PRESSES_PER_BATCH, "capped")
        harness.equal(batcher:flush(2), KeySprintRules.MAX_PRESSES_PER_BATCH, "next batch")
        harness.equal(batcher:flush(3), 6, "remainder")
    end)

    suite:test("held presses are bounded so a stuck key cannot grow memory", function()
        local batcher = PressBatcher.new(0.25)
        for _ = 1, 100000 do
            batcher:press()
        end
        batcher:flush(0)
        local total = 0
        for step = 1, 100 do
            total += batcher:flush(step)
        end
        harness.isTrue(total <= PressBatcher.MAX_PENDING, "bounded")
    end)
end
