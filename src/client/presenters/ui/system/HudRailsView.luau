--!strict
--[[
    HUD rails view: places HUD tiles where the pure plan (uisystem/HudRails) says. The plan
    guarantees no overlap, nothing outside the usable area, touch-sized tiles, and a clear lower
    band on touch devices for the Roblox thumbstick and jump button. A tile is the kit
    "hud.button" piece (icon + notification badge, Studded native) or a plain square button.
    The view only moves tiles: reflow happens by calling `layout` again with a new environment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HudRails = require(Shared.features.uisystem.HudRails)
local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local UiEnv = require(script.Parent.UiEnv)

export type TileSpec = {
    id: string,
    icon: string?,
    rail: "left" | "right" | "bottom",
    onActivated: () -> (),
}

export type Tile = {
    id: string,
    root: GuiButton,
    -- The kit notification badge frame (nil on plain tiles).
    badge: GuiObject?,
}

export type View = {
    tiles: { Tile },
    -- Positions every tile for the environment. Returns the plan problems (empty when fine).
    layout: (self: View, env: UiEnv.UiEnv) -> { string },
}

-- Share of the height kept free at the lower sides on touch devices (thumbstick and jump).
local TOUCH_RESERVE = 0.42

local HudRailsView = {}

local function buildTile(env: UiEnv.UiEnv, parent: Instance, spec: TileSpec): Tile
    local tokens = env.tokens
    local piece = env.skin:cloneSlot("hud.button")
    local button: GuiButton
    local badge: GuiObject? = nil
    if piece ~= nil and piece:IsA("GuiButton") then
        button = piece
        local iconPart = env.skin:part(piece, "hud.button", "icon")
        if iconPart:IsA("ImageLabel") and spec.icon ~= nil then
            iconPart.Image = spec.icon
        end
        local badgePart = env.skin:part(piece, "hud.button", "badge")
        if badgePart:IsA("GuiObject") then
            badge = badgePart
            badgePart.Visible = false
        end
    else
        local plain = Instance.new("TextButton")
        plain.Text = ""
        plain.BackgroundColor3 = Atoms.color(tokens.palette.surfaceRaised)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, tokens.radius.md)
        corner.Parent = plain
        if spec.icon ~= nil then
            local image = Instance.new("ImageLabel")
            image.Name = "Icon"
            image.BackgroundTransparency = 1
            image.Image = spec.icon
            image.Size = UDim2.fromScale(0.7, 0.7)
            image.AnchorPoint = Vector2.new(0.5, 0.5)
            image.Position = UDim2.fromScale(0.5, 0.5)
            image.Parent = plain
        end
        button = plain
    end
    button.Name = `Tile_{spec.id}`
    button.AnchorPoint = Vector2.zero
    -- The kit sizes by screen fraction with an aspect constraint; the plan owns size and place.
    local aspect = button:FindFirstChildOfClass("UIAspectRatioConstraint")
    if aspect ~= nil then
        aspect:Destroy()
    end
    Atoms.touchFloor(button, tokens)
    button.Activated:Connect(spec.onActivated)
    button.Parent = parent
    return { id = spec.id, root = button, badge = badge }
end

--- `parent` is SafeAreaRoot.content. Tiles are created once; `layout` places them.
function HudRailsView.new(env: UiEnv.UiEnv, parent: Instance, specs: { TileSpec }): View
    local tiles: { Tile } = {}
    local rails: { [string]: { Tile } } = { left = {}, right = {}, bottom = {} }
    for _, spec in specs do
        local tile = buildTile(env, parent, spec)
        table.insert(tiles, tile)
        table.insert(rails[spec.rail], tile)
    end

    local view = {} :: View
    view.tiles = tiles

    function view.layout(_self: View, newEnv: UiEnv.UiEnv): { string }
        local reserve = if newEnv.deviceClass == "phone" or newEnv.deviceClass == "tablet"
            then TOUCH_RESERVE
            else 0
        local plan = HudRails.plan(
            newEnv.usable,
            { left = #rails.left, right = #rails.right, bottom = #rails.bottom },
            reserve,
            newEnv.tokens
        )
        local cursor: { [string]: number } = { left = 0, right = 0, bottom = 0 }
        for _, placed in plan.tiles do
            cursor[placed.rail] += 1
            local tile = rails[placed.rail][cursor[placed.rail]]
            -- The content frame starts at the usable corner, so subtract it.
            tile.root.Position =
                UDim2.fromOffset(placed.rect.x - newEnv.usable.x, placed.rect.y - newEnv.usable.y)
            tile.root.Size = UDim2.fromOffset(placed.rect.width, placed.rect.height)
            tile.root.Visible = true
        end
        for rail, list in rails do
            for index = cursor[rail] + 1, #list do
                list[index].root.Visible = false
            end
        end
        DevGuard.requireAll(plan.problems)
        return plan.problems
    end

    view:layout(env)
    return view
end

return HudRailsView
