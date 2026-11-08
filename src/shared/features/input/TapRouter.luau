--!strict
--[[
    Pure routing of "tap anywhere" (ADR 0038): every input that may mine goes through here, so one
    place decides whether it swings. Engine side only translates events into these calls.

    Input blockers: `addBlocker(fn)` registers a function that answers "is input blocked right now?"
    (a modal menu is open, the welcome-back card is up). While any blocker answers true NO input
    calls `tap`: mouse, touch, the keyboard bind and the gamepad trigger all consult it. The menus
    of F5 register themselves here.
]]

local TapFilter = require("./TapFilter")

export type Point = { x: number, y: number }

export type Deps = {
    -- One hand swing. `position` is where it landed (InputObject.Position space), nil for the
    -- keyboard and the gamepad.
    tap: (position: Point?) -> (),
    -- The mouse (or a bound key) is held down or let go.
    setHeld: (held: boolean) -> (),
    now: () -> number,
}

export type Router = {
    addBlocker: (self: Router, blocker: () -> boolean) -> (),
    blocked: (self: Router) -> boolean,
    mouseBegan: (self: Router, processed: boolean, position: Point) -> (),
    mouseEnded: (self: Router) -> (),
    touchBegan: (self: Router, id: unknown, processed: boolean, position: Point) -> (),
    touchEnded: (self: Router, id: unknown, position: Point) -> (),
    -- The keyboard and gamepad bound action.
    action: (self: Router, began: boolean) -> (),
}

type Start = { position: Point, at: number }

local TapRouter = {}

function TapRouter.new(deps: Deps): Router
    local blockers: { () -> boolean } = {}
    local touches: { [unknown]: Start } = {}

    local router = {} :: Router

    function router.addBlocker(_self: Router, blocker: () -> boolean)
        table.insert(blockers, blocker)
    end

    function router.blocked(_self: Router): boolean
        for _, blocker in blockers do
            if blocker() then
                return true
            end
        end
        return false
    end

    function router.mouseBegan(self: Router, processed: boolean, position: Point)
        if not TapFilter.beginsTap("MouseButton1", processed, self:blocked()) then
            return
        end
        deps.tap(position)
        deps.setHeld(true)
    end

    function router.mouseEnded(_self: Router)
        deps.setHeld(false)
    end

    function router.touchBegan(self: Router, id: unknown, processed: boolean, position: Point)
        if TapFilter.beginsTap("Touch", processed, self:blocked()) then
            touches[id] = { position = position, at = deps.now() }
        end
    end

    function router.touchEnded(self: Router, id: unknown, position: Point)
        local start = touches[id]
        if start == nil then
            return
        end
        touches[id] = nil
        local dx, dy = position.x - start.position.x, position.y - start.position.y
        local travel = math.sqrt(dx * dx + dy * dy)
        if
            TapFilter.completesTap(travel, deps.now() - start.at)
            and TapFilter.allowsAction(self:blocked())
        then
            deps.tap(position)
        end
    end

    function router.action(self: Router, began: boolean)
        if began then
            if TapFilter.allowsAction(self:blocked()) then
                deps.tap(nil)
                deps.setHeld(true)
            end
        else
            deps.setHeld(false)
        end
    end

    return router
end

return TapRouter
