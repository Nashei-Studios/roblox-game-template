--!strict
local Config = require("../../../src/shared/Config")
local ControlRegistry = require("../../../src/shared/features/ui/ControlRegistry")
local InputScheme = require("../../../src/shared/features/ui/InputScheme")
local InspectView = require("../../../src/shared/features/inspect/InspectView")
local PerfBudget = require("../../../src/shared/perf/PerfBudget")
local harness = require("../../harness")

local CFG = InspectView.default
local PANEL: InspectView.Rect = { x = 100, y = 50, width = 400, height = 200 }

local function opened(): InspectView.State
    return InspectView.open(CFG, "pick_07")
end

local function near(actual: number, expected: number, label: string)
    harness.isTrue(math.abs(actual - expected) < 1e-6, `{label}: expected {expected}, got {actual}`)
end

return function(suite: harness.Harness)
    suite:test("the default config is valid and part of Config.default", function()
        harness.equal(#InspectView.validate(CFG), 0, "default valid")
        harness.isTrue(Config.default.inspect == CFG, "wired in Config")
        local broken: Config.GameConfig = table.clone(Config.default)
        broken.inspect = table.clone(CFG)
        if broken.inspect ~= nil then
            broken.inspect.closeKeys = {}
        end
        harness.equal(
            #Config.validate(broken),
            #Config.validate(Config.default) + 1,
            "Config.validate reports an invalid inspect"
        )
    end)

    suite:test("validate rejects bad limits", function()
        local bad = table.clone(CFG)
        bad.pitchMin = 70
        bad.zoomDefault = 5
        bad.stickDeadzone = 1
        bad.yawDegreesPerPixel = 0
        harness.equal(#InspectView.validate(bad), 4, "four problems")
        local zero = table.clone(CFG)
        zero.zoomMin = 0
        zero.wheelStep = 0
        harness.equal(#InspectView.validate(zero), 2, "zoom floor and speeds")
    end)

    suite:test(
        "closed holds no WorldModel, open holds exactly one, close returns to none",
        function()
            local closed = InspectView.closed(CFG)
            harness.equal(InspectView.worldModelCount(closed), 0, "closed")
            local state = opened()
            harness.equal(InspectView.worldModelCount(state), 1, "open")
            harness.equal(state.itemId, "pick_07", "item")
            harness.equal(
                InspectView.worldModelCount(InspectView.close(CFG, state)),
                0,
                "after close"
            )
            -- Repeated opens never add a second model: the count is a function of the state.
            local again = InspectView.open(CFG, "pick_08")
            harness.equal(InspectView.worldModelCount(again), 1, "reopen on another item")
            harness.equal(again.itemId, "pick_08", "swapped")
        end
    )

    suite:test("opening resets the framing; reset keeps the item", function()
        local turned = InspectView.drag(CFG, opened(), 200, 100)
        local zoomed = InspectView.wheel(CFG, turned, 3)
        local fresh = InspectView.reset(CFG, zoomed)
        harness.equal(fresh.yaw, InspectView.START_YAW, "yaw")
        harness.equal(fresh.pitch, InspectView.START_PITCH, "pitch")
        harness.equal(fresh.zoom, CFG.zoomDefault, "zoom")
        harness.equal(fresh.itemId, "pick_07", "item kept")
        local closed = InspectView.closed(CFG)
        harness.isTrue(InspectView.reset(CFG, closed) == closed, "reset of closed is a no-op")
    end)

    suite:test("every input is ignored while closed", function()
        local closed = InspectView.closed(CFG)
        harness.isTrue(InspectView.drag(CFG, closed, 50, 50) == closed, "drag")
        harness.isTrue(InspectView.stick(CFG, closed, 1, 1, 0.1) == closed, "stick")
        harness.isTrue(InspectView.wheel(CFG, closed, 1) == closed, "wheel")
        harness.isTrue(InspectView.pinch(CFG, closed, 100, 200) == closed, "pinch")
        harness.isTrue(InspectView.triggers(CFG, closed, 0, 1, 0.1) == closed, "triggers")
        harness.isTrue(InspectView.tap(CFG, closed, 0, 0, PANEL) == closed, "tap")
    end)

    suite:test("drag rotates yaw (wrapped) and pitch (clamped)", function()
        local right = InspectView.drag(CFG, opened(), 100, 0)
        near(right.yaw, InspectView.START_YAW + 50, "yaw")
        near(right.pitch, InspectView.START_PITCH, "pitch untouched")
        local wrapped = InspectView.drag(CFG, opened(), -100, 0)
        near(wrapped.yaw, 335, "wraps below zero")
        local high = InspectView.drag(CFG, opened(), 0, 10000)
        near(high.pitch, CFG.pitchMax, "pitch top clamp")
        local low = InspectView.drag(CFG, opened(), 0, -10000)
        near(low.pitch, CFG.pitchMin, "pitch bottom clamp")
    end)

    suite:test("the stick has a deadzone, a rescaled range and a clamp", function()
        local still = InspectView.stick(CFG, opened(), 0.1, 0.1, 1)
        harness.equal(still.yaw, InspectView.START_YAW, "inside deadzone")
        harness.equal(still.pitch, InspectView.START_PITCH, "inside deadzone pitch")
        local full = InspectView.stick(CFG, opened(), 1, 0, 0.5)
        near(full.yaw, InspectView.START_YAW + CFG.stickDegreesPerSecond * 0.5, "full right")
        local up = InspectView.stick(CFG, opened(), 0, 1, 0.2)
        near(up.pitch, InspectView.START_PITCH - CFG.stickDegreesPerSecond * 0.2, "up tips away")
        local capped = InspectView.stick(CFG, opened(), 0, 5, 100)
        near(capped.pitch, CFG.pitchMin, "pitch clamp")
        local left = InspectView.stick(CFG, opened(), -1, 0, 0.5)
        near(left.yaw, (InspectView.START_YAW - 80) % 360, "left wraps")
        harness.isTrue(
            InspectView.stick(CFG, opened(), 1, 1, 0).yaw == InspectView.START_YAW,
            "dt 0"
        )
    end)

    suite:test("wheel zooms in and out and clamps", function()
        near(InspectView.wheel(CFG, opened(), 1).zoom, 1 + CFG.wheelStep, "in")
        near(InspectView.wheel(CFG, opened(), -1).zoom, 1 - CFG.wheelStep, "out")
        near(InspectView.wheel(CFG, opened(), 1000).zoom, CFG.zoomMax, "max")
        near(InspectView.wheel(CFG, opened(), -1000).zoom, CFG.zoomMin, "min")
    end)

    suite:test("pinch scales by the finger ratio and ignores bad distances", function()
        near(InspectView.pinch(CFG, opened(), 100, 150).zoom, 1.5, "spread")
        near(InspectView.pinch(CFG, opened(), 200, 100).zoom, CFG.zoomMin, "pinch in clamps")
        near(InspectView.pinch(CFG, opened(), 100, 10000).zoom, CFG.zoomMax, "max")
        local state = opened()
        harness.isTrue(InspectView.pinch(CFG, state, 0, 100) == state, "zero previous")
        harness.isTrue(InspectView.pinch(CFG, state, 100, 0) == state, "zero now")
    end)

    suite:test("triggers zoom with their own deadzone and cancel each other", function()
        local state = opened()
        harness.equal(InspectView.triggers(CFG, state, 0.05, 0.05, 1).zoom, 1, "deadzone")
        near(
            InspectView.triggers(CFG, state, 0, 1, 0.5).zoom,
            1 + CFG.triggerZoomPerSecond * 0.5,
            "in"
        )
        near(
            InspectView.triggers(CFG, state, 1, 0, 0.1).zoom,
            1 - CFG.triggerZoomPerSecond * 0.1,
            "out"
        )
        near(InspectView.triggers(CFG, state, 1, 1, 1).zoom, 1, "equal triggers cancel")
        near(InspectView.triggers(CFG, state, 0, 1, 100).zoom, CFG.zoomMax, "clamp")
        harness.isTrue(InspectView.triggers(CFG, state, 0, 1, 0) == state, "dt 0")
    end)

    suite:test("a tap outside the panel closes it, inside keeps it open", function()
        local state = opened()
        harness.isTrue(InspectView.tap(CFG, state, 300, 150, PANEL) == state, "inside")
        harness.isTrue(InspectView.tap(CFG, state, 100, 50, PANEL) == state, "edge is inside")
        harness.isFalse(InspectView.tap(CFG, state, 10, 10, PANEL).open, "outside left")
        harness.isFalse(InspectView.tap(CFG, state, 300, 400, PANEL).open, "outside below")
    end)

    suite:test("Escape and B close, Y opens, other keys do nothing", function()
        harness.isTrue(InspectView.isCloseKey(CFG, "Escape"), "escape")
        harness.isTrue(InspectView.isCloseKey(CFG, "ButtonB"), "B")
        harness.isFalse(InspectView.isCloseKey(CFG, "ButtonA"), "A")
        harness.isTrue(InspectView.isOpenKey(CFG, "ButtonY"), "Y")
        harness.isFalse(InspectView.isOpenKey(CFG, "Escape"), "escape does not open")
    end)

    suite:test("camera distance shrinks as zoom grows", function()
        local state = InspectView.wheel(CFG, opened(), 1)
        near(InspectView.cameraDistance(state, 10), 10 / (1 + CFG.wheelStep), "distance")
    end)

    suite:test("controls register for every scheme: button or hint, never neither", function()
        local registry = ControlRegistry.new()
        InspectView.register(registry, CFG)
        for _, id in { InspectView.CLOSE_ID, InspectView.OPEN_ID } do
            harness.isTrue(ControlRegistry.visibleOn(registry, id, InputScheme.TOUCH), `{id} touch`)
            harness.isTrue(
                ControlRegistry.visibleOn(registry, id, InputScheme.KEYBOARD),
                `{id} keyboard`
            )
            harness.isFalse(
                ControlRegistry.visibleOn(registry, id, InputScheme.GAMEPAD),
                `{id} pad button`
            )
        end
        harness.equal(
            ControlRegistry.hintFor(registry, InspectView.CLOSE_ID, "gamepad"),
            "B",
            "close hint"
        )
        harness.equal(
            ControlRegistry.hintFor(registry, InspectView.OPEN_ID, "gamepad"),
            "Y",
            "open hint"
        )
        local noPad = table.clone(CFG)
        noPad.closeKeys = { "Escape" }
        noPad.openKeys = {}
        local second = ControlRegistry.new()
        InspectView.register(second, noPad)
        harness.equal(
            ControlRegistry.hintFor(second, InspectView.CLOSE_ID, "gamepad"),
            nil,
            "no pad key"
        )
    end)

    suite:test("the budget accepts the template model and rejects an oversized one", function()
        local budget = PerfBudget.inspect
        harness.isTrue(budget ~= nil, "PerfBudget.inspect exists")
        if budget == nil then
            return
        end
        harness.equal(#InspectView.budgetProblems(budget.maxParts, 1, budget), 0, "at the cap")
        harness.equal(#InspectView.budgetProblems(budget.maxParts + 1, 1, budget), 1, "parts")
        harness.equal(
            #InspectView.budgetProblems(1, budget.maxWorldModels + 1, budget),
            1,
            "models"
        )
        harness.equal(#InspectView.budgetProblems(1000, 9, budget), 2, "both")
    end)
end
