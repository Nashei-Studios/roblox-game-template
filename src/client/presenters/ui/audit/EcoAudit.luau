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
    registered, and registered controls visible on a scheme that does not list them. Excluded from
    line coverage (engine code); unverified in the engine until run in a playtest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControlRegistry = require(Shared.features.ui.ControlRegistry)
local EcoRules = require(Shared.features.ui.audit.EcoRules)
local Finding = require(Shared.features.ui.audit.Finding)

export type Options = {
    scope: string,
    -- The spacing token in px that siblings and card text must keep (tokens.spacing.sm).
    minGap: number,
    -- Active input scheme and the registry, to check controls. Both nil skips those rules.
    scheme: string?,
    registry: ControlRegistry.Registry?,
    -- Instance names of the HUD buttons that must be registered.
    hudButtons: { string }?,
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
                        item.TextFits,
                        item:GetAttribute("Truncatable") == true
                    )
                )
            end
        end
        if item:IsA("GuiButton") and options.hudButtons ~= nil then
            if table.find(options.hudButtons, item.Name) ~= nil then
                table.insert(visibleControls, item.Name)
            end
        end
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
