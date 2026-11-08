--!strict
--[[
    Runtime UI audit (docs/ui-audit.md). Run it in a playtest through `execute_luau` (datamodel
    Client), see scripts/ui-audit-runtime.md. For each scenario (the HUD, every menu) and each
    viewport it parents a clone of the live UI into a root Frame of that exact size, waits a layout
    pass, measures, and returns a JSON-ready report. Nothing is changed in the live UI.

    Why a root Frame and not a real resize: Studio cannot set the viewport from a script, but a
    Frame of W x H resolves every scale size, aspect constraint and layout inside it exactly as a
    screen of that size would. Sizes that depend on the camera viewport in code (a root UIScale)
    are recomputed by the `onViewport` hook of the scenario.

    Rules: UI-OVERLAP, UI-CLIPPED, UI-TEXT-FITS, UI-OFFSCREEN, UI-SAFE-AREA, UI-BUTTON-INERT,
    UI-COVERED (ZIndex inversion), UI-LIST-GAP, UI-CONTRAST, UI-TOUCH-44, UI-TEXT-SMALL.
    It touches the engine, so it is excluded from the line-coverage gate; the math lives in
    Geometry (unit tested).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Finding = require(Shared.features.ui.audit.Finding)
local Geometry = require(Shared.features.ui.audit.Geometry)

export type Scenario = {
    name: string,
    -- Live instances to clone: ScreenGuis (their children are cloned, insets honoured) or GuiObjects.
    sources: { Instance },
    -- Called on every clone before measuring (force a menu visible, undo an open animation).
    prepare: ((clone: GuiObject) -> ())?,
    -- Called once per viewport after parenting (recompute a UIScale that depends on the viewport).
    onViewport: ((root: Frame, size: Vector2) -> ())?,
}

export type Options = {
    viewports: { Vector2 },
    scenarios: { Scenario },
    -- Pixels of the top bar on a ScreenGui with CoreUISafeInsets.
    topInset: number?,
}

export type Report = {
    viewports: { string },
    scenarios: { string },
    total: number,
    byRule: { [string]: number },
    findings: { Finding.Finding },
}

local RuntimeAudit = {}

--- The four viewports of the visual bar: small phone, phone, large landscape phone, 1080p.
RuntimeAudit.VIEWPORTS = {
    Vector2.new(844, 390),
    Vector2.new(667, 375),
    Vector2.new(1327, 496),
    Vector2.new(1920, 1080),
}

local TOUCH_MIN = 44
local GAP_MIN = 4
local TEXT_MIN = 11
local OVERLAP_MIN_FRACTION = 0.1
local OVERLAP_MIN_AREA = 16
local CLIP_MIN_FRACTION = 0.9
local FULL_SCREEN_FRACTION = 0.9

-- AbsolutePosition of a top-level frame is not 0,0 (the engine reports it from the safe origin),
-- so every rectangle is taken relative to the emulated screen frame.
local origin = Vector2.zero

local function rectOf(item: GuiObject): Geometry.Rect
    local position, size = item.AbsolutePosition - origin, item.AbsoluteSize
    return { x = position.X, y = position.Y, width = size.X, height = size.Y }
end

local function isInteractive(item: Instance): boolean
    return item:IsA("GuiButton") or item:IsA("TextBox")
end

local function isText(item: Instance): boolean
    return item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")
end

local function ignored(item: GuiObject): boolean
    return item:GetAttribute("AuditIgnore") == true or string.match(item.Name, "Shadow$") ~= nil
end

local function effectivelyVisible(item: GuiObject, stop: Instance): boolean
    local current: Instance? = item
    while current ~= nil and current ~= stop do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("CanvasGroup") and current.GroupTransparency >= 1 then
            return false
        end
        current = current.Parent
    end
    return true
end

local function pathOf(item: Instance, stop: Instance): string
    local names: { string } = {}
    local current: Instance? = item
    while current ~= nil and current ~= stop do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return table.concat(names, ".")
end

--- Fraction of `item` that is not cut by the clipping ancestors, ignoring the axis a scroller scrolls.
local function unclippedFraction(item: GuiObject, stop: Instance): number
    local own = rectOf(item)
    local fraction = 1
    local current = item.Parent
    while current ~= nil and current ~= stop do
        if current:IsA("GuiObject") then
            local clips = current:IsA("CanvasGroup")
                or current:IsA("ScrollingFrame")
                or current.ClipsDescendants
            if clips then
                local window = rectOf(current)
                local xOk = Geometry.contains(
                    { x = window.x, y = -1e6, width = window.width, height = 2e6 },
                    { x = own.x, y = 0, width = own.width, height = 1 },
                    0.5
                )
                local yOk = Geometry.contains(
                    { x = -1e6, y = window.y, width = 2e6, height = window.height },
                    { x = 0, y = own.y, width = 1, height = own.height },
                    0.5
                )
                if current:IsA("ScrollingFrame") then
                    local direction = current.ScrollingDirection
                    if direction == Enum.ScrollingDirection.Y then
                        yOk = true
                    elseif direction == Enum.ScrollingDirection.X then
                        xOk = true
                    else
                        xOk, yOk = true, true
                    end
                end
                if not (xOk and yOk) then
                    fraction = math.min(fraction, Geometry.visibleFraction(window, own))
                end
            end
        end
        current = current.Parent
    end
    return fraction
end

--- Visible rectangle: the item's rectangle cut by every clipping ancestor (scrollers included).
local function visibleFractionInWindows(item: GuiObject, stop: Instance): number
    local own = rectOf(item)
    local fraction = 1
    local current = item.Parent
    while current ~= nil and current ~= stop do
        if current:IsA("GuiObject") then
            if
                current:IsA("CanvasGroup")
                or current:IsA("ScrollingFrame")
                or current.ClipsDescendants
            then
                fraction = math.min(fraction, Geometry.visibleFraction(rectOf(current), own))
            end
        end
        current = current.Parent
    end
    return fraction
end

local function isAncestorOf(first: Instance, second: Instance): boolean
    return first:IsAncestorOf(second) or second:IsAncestorOf(first)
end

--- True when `above` is drawn over `below` (Sibling ZIndexBehavior: ZIndex, then tree order).
local function drawnAbove(above: GuiObject, below: GuiObject): boolean
    local chainA: { Instance } = {}
    local current: Instance? = above
    while current ~= nil do
        table.insert(chainA, 1, current)
        current = current.Parent
    end
    local chainB: { Instance } = {}
    current = below
    while current ~= nil do
        table.insert(chainB, 1, current)
        current = current.Parent
    end
    local depth = 1
    while (chainA[depth + 1] :: Instance?) ~= nil and chainA[depth + 1] == chainB[depth + 1] do
        depth += 1
    end
    local branchA, branchB = chainA[depth + 1] :: Instance?, chainB[depth + 1] :: Instance?
    if branchA == nil or branchB == nil then
        return branchA ~= nil
    end
    local zA = if branchA:IsA("GuiObject") then branchA.ZIndex else 0
    local zB = if branchB:IsA("GuiObject") then branchB.ZIndex else 0
    if zA ~= zB then
        return zA > zB
    end
    local parent = chainA[depth]
    for _, child in parent:GetChildren() do
        if child == branchA then
            return false
        elseif child == branchB then
            return true
        end
    end
    return false
end

local function inScroller(item: GuiObject): boolean
    return item:FindFirstAncestorWhichIsA("ScrollingFrame") ~= nil
end

--- True for an invisible overlay (no fill, image or text) that exists only to catch taps.
local function isHitZone(item: GuiObject): boolean
    if item.BackgroundTransparency < 1 then
        return false
    end
    if (item:IsA("ImageButton") or item:IsA("ImageLabel")) and item.Image ~= "" then
        return false
    end
    if isText(item) and (item :: TextLabel).Text ~= "" then
        return false
    end
    return true
end

--- A visual button and its transparent hit zone overlap on purpose.
local function isHitZonePair(first: GuiObject, second: GuiObject): boolean
    return isHitZone(first) or isHitZone(second)
end

--- True when `item` hides what is under it: it sinks taps or is an opaque non-text fill.
local function paints(item: GuiObject): boolean
    if item:IsA("GuiButton") or item.Active then
        return not isHitZone(item)
    end
    return item.BackgroundTransparency < 0.5 and not isText(item)
end

local function backdropFor(item: GuiObject, stop: Instance): (GuiObject?, { Color3 })
    local current: Instance? = item
    while current ~= nil and current ~= stop do
        if current:IsA("GuiObject") and current.BackgroundTransparency < 0.5 then
            local colors: { Color3 } = { current.BackgroundColor3 }
            local gradient = current:FindFirstChildOfClass("UIGradient")
            if gradient ~= nil and gradient.Enabled then
                colors = {}
                for _, keypoint in gradient.Color.Keypoints do
                    table.insert(colors, keypoint.Value)
                end
            end
            return current, colors
        end
        current = current.Parent
    end
    return nil, {}
end

local function luminanceOf(color: Color3): number
    return Geometry.luminance(color.R, color.G, color.B)
end

local function outlineColor(item: GuiObject): Color3?
    for _, child in item:GetChildren() do
        if
            child:IsA("UIStroke")
            and child.Enabled
            and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
            and child.Transparency < 0.5
        then
            local solid = if child.StrokeSizingMode == Enum.StrokeSizingMode.FixedSize
                then child.Thickness >= 1.5
                else child.Thickness >= 0.02
            if solid then
                return child.Color
            end
        end
    end
    local text = item :: TextLabel
    if text.TextStrokeTransparency < 0.5 then
        return text.TextStrokeColor3
    end
    return nil
end

type Context = {
    scope: string,
    stop: Instance,
    out: { Finding.Finding },
}

local function add(
    context: Context,
    rule: string,
    severity: Finding.Severity,
    item: Instance,
    message: string
)
    table.insert(
        context.out,
        Finding.new(rule, severity, context.scope, pathOf(item, context.stop), message)
    )
end

local function auditItem(context: Context, item: GuiObject, screen: Geometry.Rect)
    local rect = rectOf(item)
    if rect.width <= 0 or rect.height <= 0 then
        return
    end
    local interactive = isInteractive(item)
    if interactive then
        if rect.width < TOUCH_MIN - 0.5 or rect.height < TOUCH_MIN - 0.5 then
            add(
                context,
                "UI-TOUCH-44",
                "error",
                item,
                string.format("%.0fx%.0f px is under %d", rect.width, rect.height, TOUCH_MIN)
            )
        end
        if rect.width * rect.height > screen.width * screen.height * FULL_SCREEN_FRACTION then
            return
        end
        if
            item:IsA("GuiButton")
            and not item.AutoButtonColor
            and item:FindFirstChild("PressScale") == nil
            and item:GetAttribute("StateLess") ~= true
        then
            add(
                context,
                "UI-BUTTON-INERT",
                "error",
                item,
                "no AutoButtonColor and no PressScale: no visible hover or press state"
            )
        end
        if item:IsA("GuiButton") and not item.Active and item.Interactable then
            add(context, "UI-BUTTON-INERT", "error", item, "Active is false: the tap is ignored")
        end
    end
    local visibleShare = visibleFractionInWindows(item, context.stop)
    if visibleShare < 0.02 then
        if interactive and not inScroller(item) then
            add(context, "UI-CLIPPED", "error", item, "interactive element entirely clipped")
        end
        return
    end
    if interactive or isText(item) then
        local clipped = unclippedFraction(item, context.stop)
        if clipped < CLIP_MIN_FRACTION then
            add(
                context,
                "UI-CLIPPED",
                "error",
                item,
                string.format("%.0f%% inside its clipping parent", clipped * 100)
            )
        end
        local onScreen = Geometry.visibleFraction(screen, rect)
        if onScreen < CLIP_MIN_FRACTION then
            add(
                context,
                "UI-OFFSCREEN",
                "error",
                item,
                string.format("%.0f%% inside the screen", onScreen * 100)
            )
        end
    end
    if isText(item) then
        local text = item :: TextLabel
        if text.Text ~= "" and text.TextTransparency < 0.9 then
            local fits = text.TextFits
            if not fits then
                add(context, "UI-TEXT-FITS", "error", item, "TextFits is false: the text overflows")
            end
            local height = text.TextBounds.Y
            if height > 0 and height < TEXT_MIN then
                add(
                    context,
                    "UI-TEXT-SMALL",
                    "warn",
                    item,
                    string.format("rendered %.0f px is under %d", height, TEXT_MIN)
                )
            end
            local backdrop, colors = backdropFor(item, context.stop)
            local outline = outlineColor(item)
            local needed = if height >= 24 then 3 else 4.5
            local textLum = luminanceOf(text.TextColor3)
            local best = 0
            if outline ~= nil then
                best = Geometry.contrast(textLum, luminanceOf(outline))
            end
            if backdrop ~= nil then
                local worst = math.huge
                for _, color in colors do
                    worst = math.min(worst, Geometry.contrast(textLum, luminanceOf(color)))
                end
                best = math.max(best, worst)
            end
            if backdrop == nil and outline == nil then
                add(
                    context,
                    "UI-CONTRAST",
                    "warn",
                    item,
                    "text over the world with no backdrop or outline"
                )
            elseif best < needed then
                add(
                    context,
                    "UI-CONTRAST",
                    "error",
                    item,
                    string.format("contrast %.2f is under %.1f", best, needed)
                )
            end
        end
    end
end

local function auditCovered(context: Context, items: { GuiObject })
    for _, button in items do
        if
            isInteractive(button)
            and not ignored(button)
            and visibleFractionInWindows(button, context.stop) > 0.5
        then
            local buttonRect = rectOf(button)
            if buttonRect.width * buttonRect.height > 0 then
                local center = {
                    x = buttonRect.x + buttonRect.width / 2,
                    y = buttonRect.y + buttonRect.height / 2,
                    width = 1,
                    height = 1,
                }
                for _, other in items do
                    if
                        other ~= button
                        and not isAncestorOf(button, other)
                        and paints(other)
                        and not ignored(other)
                        and Geometry.overlapArea(rectOf(other), center) > 0
                        and drawnAbove(other, button)
                        and visibleFractionInWindows(other, context.stop) > 0.5
                    then
                        local otherRect = rectOf(other)
                        local screenShare = otherRect.width * otherRect.height
                        -- Full-screen dim layers sit above on purpose when a modal is closed.
                        if screenShare < buttonRect.width * buttonRect.height * 400 then
                            add(
                                context,
                                "UI-COVERED",
                                "error",
                                button,
                                `center covered by {pathOf(other, context.stop)} (ZIndex {other.ZIndex} over {button.ZIndex})`
                            )
                            break
                        end
                    end
                end
            end
        end
    end
end

local function auditOverlap(context: Context, items: { GuiObject }, screen: Geometry.Rect)
    local buttons: { GuiObject } = {}
    for _, item in items do
        local rect = rectOf(item)
        if
            isInteractive(item)
            and not ignored(item)
            and rect.width * rect.height <= screen.width * screen.height * FULL_SCREEN_FRACTION
            and visibleFractionInWindows(item, context.stop) > 0.1
        then
            table.insert(buttons, item)
        end
    end
    for first = 1, #buttons do
        for second = first + 1, #buttons do
            local a, b = buttons[first], buttons[second]
            if not isAncestorOf(a, b) and not isHitZonePair(a, b) then
                local rectA, rectB = rectOf(a), rectOf(b)
                local area = Geometry.overlapArea(rectA, rectB)
                local smaller = math.min(rectA.width * rectA.height, rectB.width * rectB.height)
                if area >= OVERLAP_MIN_AREA and area / smaller > OVERLAP_MIN_FRACTION then
                    add(
                        context,
                        "UI-OVERLAP",
                        "error",
                        a,
                        string.format(
                            "overlaps %s by %.0f%% of the smaller",
                            pathOf(b, context.stop),
                            100 * area / smaller
                        )
                    )
                end
            end
        end
    end
end

local function auditLists(context: Context, container: Instance)
    local isList = container:FindFirstChildOfClass("UIListLayout") ~= nil
        or container:FindFirstChildOfClass("UIGridLayout") ~= nil
    if not isList then
        return
    end
    local rows: { GuiObject } = {}
    for _, child in container:GetChildren() do
        if
            child:IsA("GuiObject")
            and child.Visible
            and child.AbsoluteSize.X > 0
            and child.AbsoluteSize.Y > 0
            and visibleFractionInWindows(child, context.stop) > 0.02
        then
            table.insert(rows, child)
        end
    end
    local touching, minimum = 0, math.huge
    for first = 1, #rows do
        for second = first + 1, #rows do
            local gap = Geometry.gap(rectOf(rows[first]), rectOf(rows[second]))
            if gap < GAP_MIN then
                touching += 1
                minimum = math.min(minimum, gap)
            end
        end
    end
    if touching > 0 then
        add(
            context,
            "UI-LIST-GAP",
            "error",
            container,
            string.format("%d item pairs closer than %d px (min %.1f)", touching, GAP_MIN, minimum)
        )
    end
end

local function insetsFor(source: Instance, topInset: number): number
    local gui = if source:IsA("ScreenGui")
        then source
        else source:FindFirstAncestorWhichIsA("ScreenGui")
    if gui ~= nil and gui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets then
        return topInset
    end
    return 0
end

local function safeAreaCheck(context: Context, host: Frame, topInset: number)
    -- A tappable inside the top bar band on a gui that ignores the insets collides with the Roblox menu.
    for _, item in host:GetDescendants() do
        if item:IsA("GuiObject") and isInteractive(item) and item.Visible then
            local rect = rectOf(item)
            if rect.y < topInset - 1 and rect.y + rect.height > 0 and rect.width > 0 then
                add(
                    context,
                    "UI-SAFE-AREA",
                    "error",
                    item,
                    string.format(
                        "starts at y=%.0f inside the %d px top bar band",
                        rect.y,
                        topInset
                    )
                )
            end
        end
    end
end

local function waitLayout()
    for _ = 1, 3 do
        task.wait()
    end
end

--- Runs every scenario on every viewport and returns the report.
function RuntimeAudit.run(options: Options): Report
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    local topInset = options.topInset or GuiService:GetGuiInset().Y
    local findings: { Finding.Finding } = {}
    local viewportNames: { string } = {}
    local scenarioNames: { string } = {}
    for _, scenario in options.scenarios do
        table.insert(scenarioNames, scenario.name)
    end

    local host = Instance.new("ScreenGui")
    host.Name = "UiAuditHost"
    host.ResetOnSpawn = false
    host.ScreenInsets = Enum.ScreenInsets.None
    host.DisplayOrder = -100
    host.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    host.Parent = playerGui

    for _, viewport in options.viewports do
        local viewportName = string.format("%dx%d", viewport.X, viewport.Y)
        table.insert(viewportNames, viewportName)
        local screenRect: Geometry.Rect = { x = 0, y = 0, width = viewport.X, height = viewport.Y }
        for _, scenario in options.scenarios do
            local screen = Instance.new("Frame")
            screen.Name = "Screen"
            screen.BackgroundTransparency = 1
            screen.Active = false
            screen.ClipsDescendants = false
            screen.Size = UDim2.fromOffset(viewport.X, viewport.Y)
            screen.Parent = host
            for _, source in scenario.sources do
                local top = insetsFor(source, topInset)
                local layer = Instance.new("Frame")
                layer.Name = `Layer_{source.Name}`
                layer.BackgroundTransparency = 1
                layer.Position = UDim2.fromOffset(0, top)
                layer.Size = UDim2.new(1, 0, 1, -top)
                layer.Parent = screen
                local roots: { Instance } = if source:IsA("ScreenGui")
                    then source:GetChildren()
                    else { source }
                for _, root in roots do
                    if root:IsA("GuiObject") then
                        local clone = root:Clone()
                        if scenario.prepare ~= nil then
                            scenario.prepare(clone)
                        end
                        clone.Parent = layer
                    end
                end
            end
            if scenario.onViewport ~= nil then
                scenario.onViewport(screen, viewport)
            end
            waitLayout()
            origin = screen.AbsolutePosition
            local context: Context = {
                scope = `{scenario.name}@{viewportName}`,
                stop = screen,
                out = findings,
            }
            local items: { GuiObject } = {}
            for _, descendant in screen:GetDescendants() do
                if
                    descendant:IsA("GuiObject")
                    and effectivelyVisible(descendant, screen)
                    and not ignored(descendant)
                then
                    table.insert(items, descendant)
                end
            end
            for _, item in items do
                auditItem(context, item, screenRect)
            end
            auditOverlap(context, items, screenRect)
            auditCovered(context, items)
            for _, item in items do
                auditLists(context, item)
            end
            safeAreaCheck(context, screen, topInset)
            screen:Destroy()
        end
    end
    host:Destroy()

    local byRule: { [string]: number } = Finding.countByRule(findings)
    return {
        viewports = viewportNames,
        scenarios = scenarioNames,
        total = #findings,
        byRule = byRule,
        findings = findings,
    }
end

return RuntimeAudit
