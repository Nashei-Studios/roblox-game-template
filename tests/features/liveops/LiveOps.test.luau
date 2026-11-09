--!strict
local LiveOps = require("../../../src/shared/features/liveops/LiveOps")
local harness = require("../../harness")

local HOUR = 3600

local function config(): LiveOps.LiveOpsConfig
    return {
        slots = {
            {
                id = "zone",
                periodSeconds = HOUR,
                anchorSeconds = 0,
                entries = { "a", "b", "c" },
            },
        },
        events = {
            { id = "once", startsAt = 10 * HOUR, durationSeconds = 2 * HOUR },
            {
                id = "weekly",
                startsAt = 100 * HOUR,
                durationSeconds = 4 * HOUR,
                repeatEverySeconds = 24 * HOUR,
            },
        },
    }
end

local function rig(): { ops: LiveOps.LiveOps, clock: { now: number } }
    local clock = { now = 0 }
    local ops = LiveOps.new({
        config = config(),
        now = function()
            return clock.now
        end,
    })
    return { ops = ops, clock = clock }
end

local function entryOf(ops: LiveOps.LiveOps): string
    local state = ops:rotation("zone")
    return if state then state.entry else "none"
end

local function kinds(changes: { LiveOps.Change }): string
    local out: { string } = {}
    for _, change in changes do
        table.insert(out, change.kind)
    end
    return table.concat(out, ",")
end

return function(suite: harness.Harness)
    suite:test("validate accepts the sample and reports every bad value", function()
        harness.equal(#LiveOps.validate(config()), 0)
        local bad = config()
        bad.slots[1].periodSeconds = 0
        bad.slots[1].entries = {}
        bad.events[1].durationSeconds = 0
        bad.events[2].repeatEverySeconds = HOUR
        bad.events[2].id = "once"
        harness.equal(#LiveOps.validate(bad), 5)
    end)

    suite:test("a rotation cycles its entries one period at a time", function()
        local r = rig()
        harness.equal(entryOf(r.ops), "a")
        r.clock.now = HOUR
        harness.equal(entryOf(r.ops), "b")
        r.clock.now = 3 * HOUR - 1
        harness.equal(entryOf(r.ops), "c")
        r.clock.now = 3 * HOUR
        harness.equal(entryOf(r.ops), "a")
    end)

    suite:test("the state carries absolute boundaries and the seconds left", function()
        local r = rig()
        r.clock.now = HOUR + 600
        local state = r.ops:rotation("zone")
        harness.isTrue(state ~= nil, "slot exists")
        if state then
            harness.equal(state.periodIndex, 1)
            harness.equal(state.startsAt, HOUR)
            harness.equal(state.endsAt, 2 * HOUR)
            harness.equal(state.secondsLeft, HOUR - 600)
        end
        harness.isTrue(r.ops:rotation("missing") == nil, "unknown slot")
    end)

    suite:test("the anchor shifts the boundaries and times before it still map in range", function()
        local slot: LiveOps.RotationSlot =
            { id = "s", periodSeconds = 100, anchorSeconds = 50, entries = { "x", "y" } }
        harness.equal(LiveOps.rotationAt(slot, 50).entry, "x")
        harness.equal(LiveOps.rotationAt(slot, 149).entry, "x")
        harness.equal(LiveOps.rotationAt(slot, 150).entry, "y")
        harness.equal(LiveOps.rotationAt(slot, 49).entry, "y")
        harness.equal(LiveOps.rotationAt(slot, -51).periodIndex, -2)
    end)

    suite:test("a one-off event is active only inside its window", function()
        local r = rig()
        harness.isFalse(r.ops:isActive("once"), "before")
        r.clock.now = 10 * HOUR
        harness.isTrue(r.ops:isActive("once"), "start is inclusive")
        r.clock.now = 12 * HOUR
        harness.isFalse(r.ops:isActive("once"), "end is exclusive")
        harness.isFalse(r.ops:isActive("unknown"), "unknown event")
    end)

    suite:test("a recurring event comes back every period", function()
        local r = rig()
        r.clock.now = 100 * HOUR + 10
        harness.isTrue(r.ops:isActive("weekly"), "first occurrence")
        r.clock.now = 105 * HOUR
        harness.isFalse(r.ops:isActive("weekly"), "between occurrences")
        r.clock.now = 124 * HOUR + 1
        harness.isTrue(r.ops:isActive("weekly"), "second occurrence")
        local active = r.ops:activeEvents()
        harness.equal(#active, 1)
        harness.equal(active[1].startsAt, 124 * HOUR)
        harness.equal(active[1].secondsLeft, 4 * HOUR - 1)
    end)

    suite:test("poll records a baseline first and then reports each change once", function()
        local r = rig()
        harness.equal(kinds(r.ops:poll()), "")
        harness.equal(kinds(r.ops:poll()), "")
        r.clock.now = HOUR
        harness.equal(kinds(r.ops:poll()), "rotation")
        harness.equal(kinds(r.ops:poll()), "")
        r.clock.now = 10 * HOUR
        harness.equal(kinds(r.ops:poll()), "rotation,event_started")
        r.clock.now = 12 * HOUR
        harness.equal(kinds(r.ops:poll()), "rotation,event_ended")
    end)

    suite:test("snapshot lists every rotation and the active events", function()
        local r = rig()
        r.clock.now = 11 * HOUR
        local snapshot = r.ops:snapshot()
        harness.equal(#snapshot.rotations, 1)
        harness.equal(#snapshot.activeEvents, 1)
    end)
end
