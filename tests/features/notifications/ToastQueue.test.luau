--!strict
local ToastQueue = require("../../../src/shared/features/notifications/ToastQueue")
local harness = require("../../harness")

local function toast(kind: string, text: string, at: number): ToastQueue.Pending
    return {
        kind = kind,
        text = text,
        style = "info",
        durationSeconds = 3,
        sound = nil,
        enqueuedAt = at,
    }
end

local function newQueue(): ToastQueue.ToastQueue
    return ToastQueue.new({ maxQueue = 2, dedupeSeconds = 2, maxWaitSeconds = 10 })
end

return function(suite: harness.Harness)
    suite:test("toasts come out oldest first", function()
        local queue = newQueue()
        queue:push(toast("a", "one", 0))
        queue:push(toast("b", "two", 0))
        local first = queue:pop(0)
        local second = queue:pop(0)
        harness.equal(first and first.kind or "none", "a")
        harness.equal(second and second.kind or "none", "b")
        harness.isTrue(queue:pop(0) == nil, "empty")
    end)

    suite:test("the same toast inside the dedupe window is dropped", function()
        local queue = newQueue()
        harness.equal(queue:push(toast("a", "one", 0)), "queued")
        harness.equal(queue:push(toast("a", "one", 1.9)), "deduped")
        harness.equal(queue:push(toast("a", "one", 2)), "queued")
        harness.equal(queue:size(), 2)
    end)

    suite:test("a different text is not a duplicate", function()
        local queue = newQueue()
        queue:push(toast("a", "one", 0))
        harness.equal(queue:push(toast("a", "two", 0)), "queued")
    end)

    suite:test("a full queue drops the oldest toast", function()
        local queue = newQueue()
        queue:push(toast("a", "1", 0))
        queue:push(toast("b", "2", 0))
        harness.equal(queue:push(toast("c", "3", 0)), "dropped_oldest")
        local first = queue:pop(0)
        harness.equal(first and first.kind or "none", "b")
    end)

    suite:test("stale toasts are skipped when popped", function()
        local queue = newQueue()
        queue:push(toast("old", "x", 0))
        queue:push(toast("new", "y", 9))
        local popped = queue:pop(11)
        harness.equal(popped and popped.kind or "none", "new")
    end)
end
