--!strict
--[[
    Runtime collector of the ecosystem rules (EcoRules, docs/adr/0045): measures the live GUI and
    hands plain rectangles to the pure rules. Run it in a playtest from execute_luau (datamodel
    Client), once per input scheme, after forcing each menu open:

        local Eco = require(game.Players.LocalPlayer.PlayerScripts.Client.presenters.ui.audit.EcoAudit)
        return Eco.summary(Eco.run(gui, { scope = "Shop", minGap = 8, registry = registry,
            scheme = "keyboard", hudButtons = { "Sprint", "Equip" } }))

    What it checks: sibling gaps and overlap in every list or grid, text flush to its card, a
    label that does not fit (TextFits false) and is not marked Truncatable, HUD buttons that are not
    registered, and registered controls visible on a scheme that does not list them. With `gates`
    (ADR 0061) it also samples every scroller at the start, middle and end of its travel, counts
    the scroller depth and the chrome buttons against the limit, and finds two visible buttons with
    the same destination (attribute `Destination`, or the registry entry). Excluded from
    line coverage (engine code); unverified in the engine until run in a playtest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControlRegistry = require(Shared.features.ui.ControlRegistry)
local EcoRules = require(Shared.features.ui.audit.EcoRules)
local Finding = require(Shared.features.ui.audit.Finding)
local GateRules = require(Shared.features.ui.audit.GateRules)
local UiGates = require(Shared.features.ui.UiGates)

export type Options = {
    scope: string,
    -- The spacing token in px that siblings and card text must keep (tokens.spacing.sm).
    minGap: number,
    -- Active input scheme and the registry, to check controls. Both nil skips those rules.
    scheme: string?,
    registry: ControlRegistry.Registry?,
    -- Instance names of the HUD buttons that must be registered.
    hudButtons: { string }?,
    -- The gate limits (ADR 0061); nil skips the scroll depth, button limit and destination rules.
    gates: UiGates.Gates?,
    -- "hud" or "menu": which button limit applies to this root.
    screenKind: string?,
}

local EcoAudit = {}

local function rectOf(item: GuiObject): EcoRules.Rect
    return {
        x = item.AbsolutePosition.X,
        y = item.AbsolutePosition.Y,
        width = item.AbsoluteSize.X,
        height = item.AbsoluteSize.Y,
    }
end

local function shown(item: GuiObject, root: Instance): boolean
    local current: Instance? = item
    while current ~= nil and current ~= root.Parent do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current = current.Parent
    end
    return item.AbsoluteSize.X > 0 and item.AbsoluteSize.Y > 0
end

local function pathOf(item: Instance, root: Instance): string
    local names: { string } = {}
    local current: Instance? = item
    while current ~= nil and current ~= root.Parent do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return table.concat(names, ".")
end

local function isListHost(host: Instance): boolean
    return host:FindFirstChildOfClass("UIListLayout") ~= nil
        or host:FindFirstChildOfClass("UIGridLayout") ~= nil
end

--- The scroll offsets sampled at runtime: children are read from AbsolutePosition at each one.
local function sampleScroller(scroller: ScrollingFrame, root: Instance): { GateRules.ScrollSample }
    local original = scroller.CanvasPosition
    local viewport = { width = scroller.AbsoluteSize.X, height = scroller.AbsoluteSize.Y }
    local canvas = { width = scroller.AbsoluteCanvasSize.X, height = scroller.AbsoluteCanvasSize.Y }
    local samples: { GateRules.ScrollSample } = {}
    for _, offset in GateRules.scrollPositions(viewport, canvas) do
        scroller.CanvasPosition = Vector2.new(offset.x, offset.y)
        local children: { EcoRules.Rect } = {}
        for _, child in scroller:GetChildren() do
            if child:IsA("GuiObject") and shown(child, root) then
                local rect = rectOf(child)
                -- Canvas coordinates: undo the scroll and the scroller's own screen position.
                rect.x = rect.x - scroller.AbsolutePosition.X + scroller.CanvasPosition.X
                rect.y = rect.y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y
                table.insert(children, rect)
            end
        end
        table.insert(samples, { offset = offset, children = children })
    end
    scroller.CanvasPosition = original
    return samples
end

local function scrollerDepth(scroller: Instance, root: Instance): number
    local depth = 0
    local current: Instance? = scroller
    while current ~= nil and current ~= root.Parent do
        if current:IsA("ScrollingFrame") then
            depth += 1
        end
        current = current.Parent
    end
    return depth
end

local function insideScroller(item: Instance, root: Instance): boolean
    local current = item.Parent
    while current ~= nil and current ~= root.Parent do
        if current:IsA("ScrollingFrame") then
            return true
        end
        current = current.Parent
    end
    return false
end

--- Measures `root` (a ScreenGui or any GuiObject) and returns the findings.
function EcoAudit.run(root: Instance, options: Options): { Finding.Finding }
    local findings: { Finding.Finding } = {}
    local function add(list: { Finding.Finding })
        for _, finding in list do
            table.insert(findings, finding)
        end
    end
    local everything = root:GetDescendants()
    table.insert(everything, root)
    local visibleControls: { string } = {}
    local buttonCount = 0
    local destinations: { GateRules.Destination } = {}
    for _, item in everything do
        if not item:IsA("GuiObject") and not item:IsA("LayerCollector") then
            continue
        end
        if item:IsA("GuiObject") and not shown(item, root) then
            continue
        end
        if isListHost(item) then
            local rects: { EcoRules.Rect } = {}
            for _, child in item:GetChildren() do
                if child:IsA("GuiObject") and shown(child, root) then
                    table.insert(rects, rectOf(child))
                    -- Item inner padding: the text of a row must not touch the row edge.
                    if child:IsA("Frame") or child:IsA("GuiButton") then
                        for _, text in child:GetDescendants() do
                            if
                                (text:IsA("TextLabel") or text:IsA("TextButton"))
                                and text.Text ~= ""
                                and shown(text, root)
                            then
                                add(
                                    EcoRules.cardInset(
                                        options.scope,
                                        pathOf(text, root),
                                        rectOf(child),
                                        rectOf(text),
                                        math.min(options.minGap, 4)
                                    )
                                )
                            end
                        end
                    end
                end
            end
            add(EcoRules.siblingGaps(options.scope, pathOf(item, root), rects, options.minGap))
        end
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            if item.Text ~= "" then
                add(
                    EcoRules.textLost(
                        options.scope,
                        pathOf(item, root),
                        EcoRules.textShown(
                            item.TextFits,
                            item.TextBounds.X,
                            item.TextBounds.Y,
                            item.AbsoluteSize.X,
                            item.AbsoluteSize.Y
                        ),
                        item:GetAttribute("Truncatable") == true
                    )
                )
            end
        end
        local gates = options.gates
        if gates ~= nil and item:IsA("ScrollingFrame") then
            local path = pathOf(item, root)
            add(GateRules.scrollDepth(options.scope, path, scrollerDepth(item, root), gates))
            add(
                GateRules.scrollSamples(
                    options.scope,
                    path,
                    { width = item.AbsoluteCanvasSize.X, height = item.AbsoluteCanvasSize.Y },
                    sampleScroller(item, root),
                    gates
                )
            )
        end
        if gates ~= nil and item:IsA("GuiButton") and item:GetAttribute("AuditIgnore") ~= true then
            -- Rows of a list are content (scroll rules); the chrome buttons are what is limited.
            if not insideScroller(item, root) then
                buttonCount += 1
            end
            local destination = item:GetAttribute("Destination")
            if destination == nil and options.registry ~= nil then
                local control = options.registry.controls[item.Name]
                destination = if control ~= nil then control.destination else nil
            end
            if type(destination) == "string" then
                table.insert(destinations, { name = item.Name, destination = destination })
            end
        end
        if item:IsA("GuiButton") and options.hudButtons ~= nil then
            if table.find(options.hudButtons, item.Name) ~= nil then
                table.insert(visibleControls, item.Name)
            end
        end
    end
    if options.gates ~= nil and options.scheme ~= nil then
        add(
            GateRules.buttonLimit(
                options.scope,
                options.screenKind or "menu",
                options.scheme,
                buttonCount,
                options.gates
            )
        )
        add(GateRules.duplicateDestinations(options.scope, options.scheme, destinations))
    end
    local registry = options.registry
    if registry ~= nil then
        add(EcoRules.hudRegistration(options.scope, options.hudButtons or {}, registry))
        if options.scheme ~= nil then
            add(EcoRules.controlsOnScheme(options.scope, options.scheme, visibleControls, registry))
        end
    end
    return findings
end

--- A readable digest: one line per finding.
function EcoAudit.summary(findings: { Finding.Finding }): string
    local lines = { `eco findings={#findings}` }
    for _, finding in findings do
        table.insert(lines, Finding.format(finding))
    end
    return table.concat(lines, "\n")
end

return EcoAudit
