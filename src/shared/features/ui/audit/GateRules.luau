--!strict
--[[
    Gate rules that stop the UI defects of game 1 (+1 Mining Power), decision in
    docs/adr/0061-ui-gate-rules.md. Pure functions over plain measurements and declarations, so
    they run under Lune in the static gate and in a playtest (EcoAudit collects the measurements).
    Every limit comes from UiGates (config), never from a literal here. Rule ids:

      UI-DUP-DESTINATION   two visible controls of one screen open the same menu or action
      UI-SCROLL-OVERLAP    children of a scroller overlap at some scroll position
      UI-SCROLL-OUTSIDE    a child leaves the scroller canvas at some scroll position
      UI-SCROLL-DEPTH      scrollers nested deeper than the limit
      UI-MOTION-MISSING    a modal menu lacks its open/close/hover/press motion or reduced fallback
      UI-BUTTON-LIMIT      more buttons on a screen than the limit for the scheme
      UI-TOUCH-LOCOMOTION  a locomotion button (run, stow) is shown on touch
]]

local ControlRegistry = require("../ControlRegistry")
local Finding = require("./Finding")
local Geometry = require("./Geometry")
local InputScheme = require("../InputScheme")
local UiGates = require("../UiGates")

export type Rect = Geometry.Rect
export type Finding = Finding.Finding
export type Size = { width: number, height: number }
export type Offset = { x: number, y: number }

-- A named visible control and what it opens or does.
export type Destination = { name: string, destination: string }

-- A scroller as the static layout computes it: children in canvas coordinates.
export type ScrollView = { viewport: Size, canvas: Size, children: { Rect } }

-- Children measured at one scroll offset, in canvas coordinates (what the runtime reads).
export type ScrollSample = { offset: Offset, children: { Rect } }

local GateRules = {}

-- Valid ways to drive an open or close transition.
local TRANSITIONS = { "tween", "spring" }

local function intersects(a: Rect, b: Rect, tolerance: number): boolean
    local width = math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x)
    local height = math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y)
    return width > tolerance and height > tolerance
end

--- UI-DUP-DESTINATION over the visible controls of one screen on one scheme.
function GateRules.duplicateDestinations(
    scope: string,
    scheme: string,
    items: { Destination }
): { Finding }
    local byDestination: { [string]: { string } } = {}
    local order: { string } = {}
    for _, item in items do
        local names = byDestination[item.destination]
        if names == nil then
            byDestination[item.destination] = { item.name }
            table.insert(order, item.destination)
        else
            table.insert(names, item.name)
        end
    end
    local out: { Finding } = {}
    for _, destination in order do
        local names = byDestination[destination]
        if #names > 1 then
            table.insert(
                out,
                Finding.new(
                    "UI-DUP-DESTINATION",
                    "error",
                    `{scope}@{scheme}`,
                    table.concat(names, ","),
                    `{#names} visible controls open "{destination}": keep one`
                )
            )
        end
    end
    return out
end

--- UI-DUP-DESTINATION over a registry: the controls whose button shows on `scheme`.
function GateRules.registryDuplicates(
    scope: string,
    registry: ControlRegistry.Registry,
    scheme: string
): { Finding }
    local items: { Destination } = {}
    for _, control in ControlRegistry.onScheme(registry, scheme) do
        if control.destination ~= nil then
            table.insert(items, { name = control.id, destination = control.destination })
        end
    end
    return GateRules.duplicateDestinations(scope, scheme, items)
end

--- The scroll offsets a scroller is checked at: start, middle and end of its travel. A canvas
--- that fits the viewport does not scroll, so it has one position.
function GateRules.scrollPositions(viewport: Size, canvas: Size): { Offset }
    local maxX = math.max(0, canvas.width - viewport.width)
    local maxY = math.max(0, canvas.height - viewport.height)
    if maxX == 0 and maxY == 0 then
        return { { x = 0, y = 0 } }
    end
    return { { x = 0, y = 0 }, { x = maxX / 2, y = maxY / 2 }, { x = maxX, y = maxY } }
end

--- Rectangles of a vertical list: item heights, the gap between them and the width they fill.
function GateRules.listRects(heights: { number }, padding: number, width: number): { Rect }
    local out: { Rect } = {}
    local y = 0
    for _, height in heights do
        table.insert(out, { x = 0, y = y, width = width, height = height })
        y += height + padding
    end
    return out
end

--- Length of a vertical list: the sum of the heights and the gaps between them.
function GateRules.listExtent(heights: { number }, padding: number): number
    local total = 0
    for _, height in heights do
        total += height
    end
    return total + padding * math.max(0, #heights - 1)
end

--- UI-SCROLL-OVERLAP and UI-SCROLL-OUTSIDE over children measured at several scroll offsets.
--- Children are in canvas coordinates; the canvas is the rectangle they must stay inside.
function GateRules.scrollSamples(
    scope: string,
    path: string,
    canvas: Size,
    samples: { ScrollSample },
    gates: UiGates.Gates
): { Finding }
    local tolerance = gates.tolerancePx
    local worstPairs, worstOutside = 0, 0
    local canvasRect: Rect = { x = 0, y = 0, width = canvas.width, height = canvas.height }
    for _, sample in samples do
        local pairs, outside = 0, 0
        for first = 1, #sample.children do
            if not Geometry.contains(canvasRect, sample.children[first], tolerance) then
                outside += 1
            end
            for second = first + 1, #sample.children do
                if intersects(sample.children[first], sample.children[second], tolerance) then
                    pairs += 1
                end
            end
        end
        worstPairs = math.max(worstPairs, pairs)
        worstOutside = math.max(worstOutside, outside)
    end
    local out: { Finding } = {}
    if worstPairs > 0 then
        table.insert(
            out,
            Finding.new(
                "UI-SCROLL-OVERLAP",
                "error",
                scope,
                path,
                `{worstPairs} child pairs overlap while scrolling ({#samples} positions checked)`
            )
        )
    end
    if worstOutside > 0 then
        table.insert(
            out,
            Finding.new(
                "UI-SCROLL-OUTSIDE",
                "error",
                scope,
                path,
                `{worstOutside} children leave the {canvas.width}x{canvas.height} canvas`
            )
        )
    end
    return out
end

--- Static form of the scroll rules: the computed layout is sampled at every scroll position.
function GateRules.scrollLayout(
    scope: string,
    path: string,
    view: ScrollView,
    gates: UiGates.Gates
): { Finding }
    local samples: { ScrollSample } = {}
    for _, offset in GateRules.scrollPositions(view.viewport, view.canvas) do
        table.insert(samples, { offset = offset, children = view.children })
    end
    return GateRules.scrollSamples(scope, path, view.canvas, samples, gates)
end

--- UI-SCROLL-DEPTH: `depth` is how many scrollers enclose the instance, itself included.
function GateRules.scrollDepth(
    scope: string,
    path: string,
    depth: number,
    gates: UiGates.Gates
): { Finding }
    if depth <= gates.maxNestedScroll then
        return {}
    end
    return {
        Finding.new(
            "UI-SCROLL-DEPTH",
            "error",
            scope,
            path,
            `scroller nested {depth} deep, the limit is {gates.maxNestedScroll}`
        ),
    }
end

--- UI-MOTION-MISSING: every modal menu declares how it opens and closes, that its buttons react
--- to hover and press, and what it does under reduced motion. `motionSeconds` is the theme
--- duration: zero makes any declared tween a no-op.
function GateRules.motion(
    scope: string,
    menus: { UiGates.MotionMenu },
    motionSeconds: number
): { Finding }
    local out: { Finding } = {}
    local function add(menuId: string, message: string)
        table.insert(out, Finding.new("UI-MOTION-MISSING", "error", scope, menuId, message))
    end
    for _, menu in menus do
        if not menu.modal then
            continue
        end
        local motion = menu.motion
        if motion == nil then
            add(menu.id, "modal menu declares no motion (open, close, hover, press)")
            continue
        end
        if table.find(TRANSITIONS, motion.open) == nil then
            add(menu.id, `open transition is "{motion.open}": declare tween or spring`)
        end
        if table.find(TRANSITIONS, motion.close) == nil then
            add(menu.id, `close transition is "{motion.close}": declare tween or spring`)
        end
        if not motion.hover then
            add(menu.id, "buttons declare no hover feedback")
        end
        if not motion.press then
            add(menu.id, "buttons declare no press feedback")
        end
        if motion.reduced ~= "instant" and motion.reduced ~= "fade" then
            add(menu.id, "no reduced motion fallback (instant or fade)")
        end
        if motionSeconds <= 0 then
            add(menu.id, "theme motionSeconds is zero: the declared transitions do nothing")
        end
    end
    return out
end

--- UI-BUTTON-LIMIT: `kind` is "hud" or "menu"; `count` the buttons shown on the screen.
function GateRules.buttonLimit(
    scope: string,
    kind: string,
    scheme: string,
    count: number,
    gates: UiGates.Gates
): { Finding }
    local limits = if kind == "hud" then gates.maxButtons.hud else gates.maxButtons.menu
    local limit = (limits :: any)[scheme]
    if type(limit) ~= "number" or count <= limit then
        return {}
    end
    return {
        Finding.new(
            "UI-BUTTON-LIMIT",
            "error",
            `{scope}@{scheme}`,
            kind,
            `{count} buttons, the {kind} limit on {scheme} is {limit}`
        ),
    }
end

--- UI-TOUCH-LOCOMOTION: a control of a forbidden category whose button shows on touch.
function GateRules.touchLocomotion(
    scope: string,
    registry: ControlRegistry.Registry,
    gates: UiGates.Gates
): { Finding }
    local out: { Finding } = {}
    for _, control in ControlRegistry.onScheme(registry, InputScheme.TOUCH) do
        if
            control.category ~= nil
            and table.find(gates.touchForbiddenCategories, control.category) ~= nil
        then
            table.insert(
                out,
                Finding.new(
                    "UI-TOUCH-LOCOMOTION",
                    "error",
                    `{scope}@touch`,
                    control.id,
                    `{control.category} control shown as a touch button: use the joystick or an item slot`
                )
            )
        end
    end
    return out
end

--- Button counts per scheme for the HUD controls of a registry (UI-BUTTON-LIMIT, kind "hud").
function GateRules.registryButtonLimits(
    scope: string,
    registry: ControlRegistry.Registry,
    gates: UiGates.Gates
): { Finding }
    local out: { Finding } = {}
    for _, scheme in InputScheme.ALL do
        local count = #ControlRegistry.onScheme(registry, scheme)
        for _, finding in GateRules.buttonLimit(scope, "hud", scheme, count, gates) do
            table.insert(out, finding)
        end
    end
    return out
end

return GateRules
