--!strict
--[[
    Static UI audit rules (docs/ui-audit.md). They read only properties, never layout results, so
    they run under Lune over the committed .rbxm pieces with no Studio. Layout-dependent checks
    (overlap, clipping, TextFits, contrast over the real background) live in RuntimeAudit.

    Instances are duck typed (`Inspectable`): the Lune and engine Instance types differ and the
    rules only use the API they share (IsA, GetChildren, GetDescendants, properties).
]]

local Finding = require("./Finding")
local GateRules = require("./GateRules")
local UiGates = require("../UiGates")

export type Inspectable = any
export type Finding = Finding.Finding

local StaticRules = {}

--- Reference viewport (the 844x390 landscape phone) used to turn scale sizes into pixels.
StaticRules.REFERENCE_WIDTH = 844
StaticRules.REFERENCE_HEIGHT = 390
--- Smallest tappable edge in pixels.
StaticRules.TOUCH_MIN = 44
--- Largest ScaledSize thickness a kit stroke may keep (the kit's own values).
StaticRules.KIT_STROKE_MAX = 0.2

local function pathOf(root: Inspectable, instance: Inspectable): string
    local names: { string } = {}
    local current = instance
    while current ~= nil and current ~= root.Parent do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return table.concat(names, ".")
end

local function guiChildren(parent: Inspectable): number
    local count = 0
    for _, child in parent:GetChildren() do
        if child:IsA("GuiObject") then
            count += 1
        end
    end
    return count
end

local function isText(instance: Inspectable): boolean
    return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function emptyUDim(scale: number, offset: number): boolean
    return offset <= 0 and scale <= 0
end

local function report(
    out: { Finding },
    rule: string,
    scope: string,
    root: Inspectable,
    instance: Inspectable,
    message: string
)
    table.insert(out, Finding.new(rule, "error", scope, pathOf(root, instance), message))
end

--- UI-LIST-PADDING and UI-GRID-PADDING: items inside a list or grid must not touch.
local function checkSpacing(
    root: Inspectable,
    scope: string,
    instance: Inspectable,
    out: { Finding }
)
    local container = instance.Parent
    if container == nil then
        return
    end
    if instance:IsA("UIListLayout") then
        if
            (container:IsA("ScrollingFrame") or guiChildren(container) >= 2)
            and emptyUDim(instance.Padding.Scale, instance.Padding.Offset)
        then
            report(
                out,
                "UI-LIST-PADDING",
                scope,
                root,
                instance,
                "UIListLayout Padding is 0: items touch"
            )
        end
    elseif instance:IsA("UIGridLayout") then
        local padding = instance.CellPadding
        if
            emptyUDim(padding.X.Scale, padding.X.Offset)
            or emptyUDim(padding.Y.Scale, padding.Y.Offset)
        then
            report(
                out,
                "UI-GRID-PADDING",
                scope,
                root,
                instance,
                "UIGridLayout CellPadding is 0 on an axis: cells touch"
            )
        end
    end
end

--- UI-SCROLL-CANVAS and UI-SCROLL-PADDING: a scroller sizes its canvas itself and insets its rows.
local function checkScroller(
    root: Inspectable,
    scope: string,
    instance: Inspectable,
    out: { Finding }
)
    if not instance:IsA("ScrollingFrame") then
        return
    end
    local automatic = tostring(instance.AutomaticCanvasSize) ~= "Enum.AutomaticSize.None"
    if not automatic and instance:GetAttribute("CanvasUpdater") ~= true then
        report(
            out,
            "UI-SCROLL-CANVAS",
            scope,
            root,
            instance,
            "AutomaticCanvasSize is None and no CanvasUpdater attribute"
        )
    end
    if instance:FindFirstChildOfClass("UIPadding") == nil then
        report(
            out,
            "UI-SCROLL-PADDING",
            scope,
            root,
            instance,
            "no UIPadding: rows touch the scroller edges"
        )
    end
end

--- UI-SCROLL-DEPTH: scrollers nested past the configured depth.
local function checkScrollDepth(
    root: Inspectable,
    scope: string,
    instance: Inspectable,
    out: { Finding },
    gates: UiGates.Gates
)
    if not instance:IsA("ScrollingFrame") then
        return
    end
    local depth = 0
    local current = instance
    while current ~= nil and current ~= root.Parent do
        if current:IsA("ScrollingFrame") then
            depth += 1
        end
        current = current.Parent
    end
    for _, finding in GateRules.scrollDepth(scope, pathOf(root, instance), depth, gates) do
        table.insert(out, finding)
    end
end

local function udimPixels(udim: Inspectable, basis: number): number
    return udim.Scale * basis + udim.Offset
end

--- UI-SCROLL-OVERLAP and UI-SCROLL-OUTSIDE: the layout of a scroller's children is computed from
--- its properties (list order, padding, offset sizes) and checked at every scroll position.
--- A scroller whose children are sized by the canvas itself, or laid out by a grid, is left to
--- the runtime audit.
local function checkScrollLayout(
    root: Inspectable,
    scope: string,
    instance: Inspectable,
    out: { Finding },
    gates: UiGates.Gates
)
    if not instance:IsA("ScrollingFrame") then
        return
    end
    local viewport = {
        width = udimPixels(instance.Size.X, StaticRules.REFERENCE_WIDTH),
        height = udimPixels(instance.Size.Y, StaticRules.REFERENCE_HEIGHT),
    }
    local children: { Inspectable } = {}
    for _, child in instance:GetChildren() do
        if child:IsA("GuiObject") and child.Visible then
            table.insert(children, child)
        end
    end
    if #children == 0 then
        return
    end
    local list = instance:FindFirstChildOfClass("UIListLayout")
    local view: GateRules.ScrollView
    if list ~= nil then
        if tostring(list.FillDirection) ~= "Enum.FillDirection.Vertical" then
            return
        end
        table.sort(children, function(a: Inspectable, b: Inspectable): boolean
            return a.LayoutOrder < b.LayoutOrder
        end)
        local heights: { number } = {}
        for _, child in children do
            if child.Size.Y.Scale ~= 0 then
                return
            end
            table.insert(heights, child.Size.Y.Offset)
        end
        local padding = udimPixels(list.Padding, viewport.height)
        local rects = GateRules.listRects(heights, padding, viewport.width)
        local extent = GateRules.listExtent(heights, padding)
        local automatic = tostring(instance.AutomaticCanvasSize) ~= "Enum.AutomaticSize.None"
        local canvasHeight = if automatic
            then extent
            else udimPixels(instance.CanvasSize.Y, viewport.height)
        view = {
            viewport = viewport,
            canvas = { width = viewport.width, height = canvasHeight },
            children = rects,
        }
    else
        local canvas = {
            width = math.max(viewport.width, udimPixels(instance.CanvasSize.X, viewport.width)),
            height = math.max(viewport.height, udimPixels(instance.CanvasSize.Y, viewport.height)),
        }
        local rects: { GateRules.Rect } = {}
        for _, child in children do
            table.insert(rects, {
                x = udimPixels(child.Position.X, canvas.width),
                y = udimPixels(child.Position.Y, canvas.height),
                width = udimPixels(child.Size.X, canvas.width),
                height = udimPixels(child.Size.Y, canvas.height),
            })
        end
        view = { viewport = viewport, canvas = canvas, children = rects }
    end
    for _, finding in GateRules.scrollLayout(scope, pathOf(root, instance), view, gates) do
        table.insert(out, finding)
    end
end

--- UI-TEXT-FIT: a text either scales inside a size constraint or declares a fit helper.
local function checkText(root: Inspectable, scope: string, instance: Inspectable, out: { Finding })
    if
        not isText(instance)
        or instance.Text == ""
        or instance:GetAttribute("FitHelper") == true
    then
        return
    end
    if not instance.TextScaled then
        report(
            out,
            "UI-TEXT-FIT",
            scope,
            root,
            instance,
            "TextScaled is false and no FitHelper attribute"
        )
    elseif instance:FindFirstChildOfClass("UITextSizeConstraint") == nil then
        report(out, "UI-TEXT-FIT", scope, root, instance, "TextScaled without UITextSizeConstraint")
    end
end

--- UI-TOUCH-44: a tappable is at least 44 px at the reference resolution.
local function checkTouch(root: Inspectable, scope: string, instance: Inspectable, out: { Finding })
    if not instance:IsA("GuiButton") then
        return
    end
    local constraint = instance:FindFirstChildOfClass("UISizeConstraint")
    local parent = instance.Parent
    local grid = if parent ~= nil then parent:FindFirstChildOfClass("UIGridLayout") else nil
    local sizeX, sizeY = 0, 0
    if grid ~= nil then
        local cell = grid.CellSize
        sizeX = cell.X.Scale * StaticRules.REFERENCE_WIDTH + cell.X.Offset
        sizeY = cell.Y.Scale * StaticRules.REFERENCE_HEIGHT + cell.Y.Offset
        local box = parent:FindFirstChildOfClass("UISizeConstraint")
        if box ~= nil then
            sizeX = math.max(sizeX, box.MinSize.X * cell.X.Scale)
            sizeY = math.max(sizeY, box.MinSize.Y * cell.Y.Scale)
        end
    else
        sizeX =
            math.max(if constraint ~= nil then constraint.MinSize.X else 0, instance.Size.X.Offset)
        sizeY =
            math.max(if constraint ~= nil then constraint.MinSize.Y else 0, instance.Size.Y.Offset)
    end
    if sizeX < StaticRules.TOUCH_MIN or sizeY < StaticRules.TOUCH_MIN then
        report(
            out,
            "UI-TOUCH-44",
            scope,
            root,
            instance,
            `guaranteed size {sizeX}x{sizeY} is under {StaticRules.TOUCH_MIN} px`
        )
    end
end

--- UI-KIT-STROKE: kit strokes keep their ScaledSize thickness (never rewritten).
local function checkStroke(
    root: Inspectable,
    scope: string,
    instance: Inspectable,
    out: { Finding }
)
    if
        instance:IsA("UIStroke")
        and tostring(instance.StrokeSizingMode) == "Enum.StrokeSizingMode.ScaledSize"
        and instance.Thickness > StaticRules.KIT_STROKE_MAX
    then
        report(
            out,
            "UI-KIT-STROKE",
            scope,
            root,
            instance,
            `ScaledSize thickness {instance.Thickness} is over {StaticRules.KIT_STROKE_MAX}`
        )
    end
end

--- Audits one root (and everything under it). `scope` names the file or piece. `gates` are the
--- configured limits (UiGates.default() when nil).
function StaticRules.auditRoot(root: Inspectable, scope: string, gates: UiGates.Gates?): { Finding }
    local limits = gates or UiGates.default()
    local out: { Finding } = {}
    local all: { Inspectable } = { root }
    for _, descendant in root:GetDescendants() do
        table.insert(all, descendant)
    end
    for _, instance in all do
        checkSpacing(root, scope, instance, out)
        checkScroller(root, scope, instance, out)
        checkScrollDepth(root, scope, instance, out, limits)
        checkScrollLayout(root, scope, instance, out, limits)
        checkText(root, scope, instance, out)
        checkTouch(root, scope, instance, out)
        checkStroke(root, scope, instance, out)
    end
    return out
end

return StaticRules
