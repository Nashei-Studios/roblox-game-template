--!strict
local TapFilter = require("../../../src/shared/features/input/TapFilter")
local TapRouter = require("../../../src/shared/features/input/TapRouter")
local harness = require("../../harness")

local POINT = { x = 10, y = 10 }

local function newRouter(
    clock: { now: number }
): (TapRouter.Router, { taps: number, held: boolean })
    local log = { taps = 0, held = false }
    local router = TapRouter.new({
        tap = function(_position: TapRouter.Point?)
            log.taps += 1
        end,
        setHeld = function(held: boolean)
            log.held = held
        end,
        now = function(): number
            return clock.now
        end,
    })
    return router, log
end

return function(suite: harness.Harness)
    suite:test("with an input blocker up no input calls tap", function()
        local router, log = newRouter({ now = 0 })
        local blocked = true
        router:addBlocker(function(): boolean
            return blocked
        end)
        router:mouseBegan(false, POINT)
        router:touchBegan("a", false, POINT)
        router:touchEnded("a", POINT)
        router:action(true)
        harness.equal(log.taps, 0, "mouse, touch and the bound action are all blocked")
        harness.isFalse(log.held, "nothing is held")
        blocked = false
        router:mouseBegan(false, POINT)
        harness.equal(log.taps, 1, "free again: the click taps")
        router:action(true)
        harness.equal(log.taps, 2, "and so does the bound action")
    end)

    suite:test("any one blocker is enough", function()
        local router = newRouter({ now = 0 })
        router:addBlocker(function(): boolean
            return false
        end)
        harness.isFalse(router:blocked(), "all free")
        router:addBlocker(function(): boolean
            return true
        end)
        harness.isTrue(router:blocked(), "one up")
    end)

    suite:test("a short touch without travel taps on release; a drag or a hold does not", function()
        local clock = { now = 0 }
        local router, log = newRouter(clock)
        router:touchBegan("a", false, POINT)
        clock.now = 0.1
        router:touchEnded("a", { x = 12, y = 10 })
        harness.equal(log.taps, 1, "short tap")
        router:touchBegan("b", false, POINT)
        clock.now = 0.2
        router:touchEnded("b", { x = 200, y = 10 })
        harness.equal(log.taps, 1, "drag")
        router:touchBegan("c", false, POINT)
        clock.now = 1
        router:touchEnded("c", POINT)
        harness.equal(log.taps, 1, "hold")
        router:touchEnded("never-began", POINT)
        harness.equal(log.taps, 1, "unknown touch ignored")
        router:touchBegan("d", true, POINT)
        router:touchEnded("d", POINT)
        harness.equal(log.taps, 1, "a touch the GUI took is ignored")
    end)

    suite:test("the mouse holds on press and lets go on release", function()
        local router, log = newRouter({ now = 0 })
        router:mouseBegan(false, POINT)
        harness.isTrue(log.held, "held")
        router:mouseEnded()
        harness.isFalse(log.held, "released")
        router:mouseBegan(true, POINT)
        harness.equal(log.taps, 1, "a click on a button is ignored")
    end)

    suite:test("the bound action taps and holds, then releases", function()
        local router, log = newRouter({ now = 0 })
        router:action(true)
        harness.isTrue(log.held, "held")
        harness.equal(log.taps, 1, "tapped with no position")
        router:action(false)
        harness.isFalse(log.held, "released")
    end)

    suite:test(
        "a press starts a tap only for touch or left click, free of GUI and menus",
        function()
            harness.isTrue(TapFilter.beginsTap("Touch", false, false), "touch")
            harness.isTrue(TapFilter.beginsTap("MouseButton1", false, false), "left click")
            harness.isFalse(TapFilter.beginsTap("Touch", true, false), "touch on a button")
            harness.isFalse(TapFilter.beginsTap("MouseButton1", true, false), "click on a button")
            harness.isFalse(TapFilter.beginsTap("Touch", false, true), "a menu is open")
            harness.isFalse(TapFilter.beginsTap("MouseButton2", false, false), "right click")
            harness.isFalse(TapFilter.beginsTap("Keyboard", false, false), "keyboard")
            harness.isFalse(TapFilter.beginsTap("Gamepad1", false, false), "gamepad")
        end
    )

    suite:test("a touch counts on release only when short and without travel", function()
        harness.isTrue(TapFilter.completesTap(2, 0.1), "short tap")
        harness.isTrue(TapFilter.completesTap(0, 0.29), "just under the time")
        harness.isFalse(TapFilter.completesTap(80, 0.15), "a camera drag does not count")
        harness.isFalse(TapFilter.completesTap(10, 0.1), "travel at the limit is a drag")
        harness.isFalse(TapFilter.completesTap(1, 0.5), "a long press does not count")
    end)

    suite:test("keyboard and gamepad actions are refused while blocked", function()
        harness.isTrue(TapFilter.allowsAction(false), "free")
        harness.isFalse(TapFilter.allowsAction(true), "blocked")
    end)
end
