--!strict
--[[
    Client presenter: paints one `ItemIcon.Spec`. A rounded card with the rarity background
    gradient, the item image (or its silhouette, or the swatch), the rarity frame, an optional
    glow ring and shimmer sweep, a lock tag and a count or level badge. All colors and sizes come
    from the spec and the theme tokens; no literal color lives here. `apply` repaints in place, so
    a menu keeps one view per card and calls it when ownership changes.
    Engine code: excluded from the coverage gate, kept thin. UNVERIFIED until a person checks it
    in Studio's Device Emulator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ItemIcon = require(Shared.features.ui.ItemIcon)
local UiConfig = require(Shared.features.ui.UiConfig)
local RarityShimmer = require(script.Parent.Parent.rarity.RarityShimmer)
local Widgets = require(script.Parent.Widgets)

export type Deps = {
    theme: UiConfig.Theme,
    parent: Instance,
    name: string,
    -- Text of the lock tag (from the game's strings).
    lockedText: string,
}

export type ItemIconView = {
    root: Frame,
    apply: (spec: ItemIcon.Spec) -> (),
    destroy: () -> (),
}

local ItemIconView = {}

function ItemIconView.new(deps: Deps): ItemIconView
    local theme = deps.theme
    local pad = theme.spacing.sm

    local root = Instance.new("Frame")
    root.Name = deps.name
    root.BorderSizePixel = 0
    root.BackgroundColor3 = Widgets.color(theme.palette.surface)
    root.Parent = deps.parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, theme.radius)
    corner.Parent = root
    local background = Instance.new("UIGradient")
    background.Rotation = 90
    background.Parent = root

    -- Own stroke on our own frame: the kit strokes are never touched.
    local stroke = Instance.new("UIStroke")
    stroke.Name = "Frame"
    stroke.Thickness = theme.strokeThickness * 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = root

    local glow = Instance.new("Frame")
    glow.Name = "Glow"
    glow.BackgroundTransparency = 1
    glow.Size = UDim2.fromScale(1, 1)
    glow.ZIndex = 0
    glow.Parent = root
    local glowCorner = Instance.new("UICorner")
    glowCorner.CornerRadius = UDim.new(0, theme.radius)
    glowCorner.Parent = glow
    local glowStroke = Instance.new("UIStroke")
    glowStroke.Thickness = theme.strokeThickness * 4
    glowStroke.Transparency = 0.6
    glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    glowStroke.Parent = glow

    local image = Instance.new("ImageLabel")
    image.Name = "Image"
    image.BackgroundTransparency = 1
    image.BorderSizePixel = 0
    image.ScaleType = Enum.ScaleType.Fit
    image.AnchorPoint = Vector2.new(0.5, 0.5)
    image.Position = UDim2.fromScale(0.5, 0.5)
    image.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
    image.ZIndex = 2
    image.Parent = root
    local imageCorner = Instance.new("UICorner")
    imageCorner.CornerRadius = UDim.new(0, theme.radius)
    imageCorner.Parent = image

    local shimmer = Instance.new("Frame")
    shimmer.Name = "Shimmer"
    shimmer.BackgroundColor3 = Color3.new(1, 1, 1)
    shimmer.BorderSizePixel = 0
    shimmer.Size = UDim2.fromScale(1, 1)
    shimmer.ZIndex = 3
    shimmer.Visible = false
    shimmer.Parent = root
    local shimmerCorner = Instance.new("UICorner")
    shimmerCorner.CornerRadius = UDim.new(0, theme.radius)
    shimmerCorner.Parent = shimmer
    local sweep = Instance.new("UIGradient")
    sweep.Rotation = 25
    sweep.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.45, 1),
        NumberSequenceKeypoint.new(0.5, 0.78),
        NumberSequenceKeypoint.new(0.55, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    sweep.Parent = shimmer

    local lockTag =
        Widgets.label(root, theme, "Lock", deps.lockedText, "caption", theme.palette.textPrimary)
    lockTag.AnchorPoint = Vector2.new(0.5, 1)
    lockTag.Position = UDim2.new(0.5, 0, 1, -pad)
    lockTag.Size = UDim2.new(1, -pad * 2, 0, theme.textSize.caption + pad)
    lockTag.BackgroundTransparency = 0.35
    lockTag.BackgroundColor3 = Color3.new(0, 0, 0)
    lockTag.ZIndex = 4
    lockTag.Visible = false

    local badge = Widgets.label(root, theme, "Badge", "", "caption", theme.palette.textPrimary)
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -pad, 0, pad)
    badge.AutomaticSize = Enum.AutomaticSize.XY
    badge.Size = UDim2.fromOffset(0, 0)
    badge.BackgroundTransparency = 0.25
    badge.BackgroundColor3 = Color3.new(0, 0, 0)
    badge.ZIndex = 4
    badge.Visible = false

    local stopShimmer: (() -> ())? = nil

    local function apply(spec: ItemIcon.Spec)
        if stopShimmer ~= nil then
            stopShimmer()
            stopShimmer = nil
        end
        local fx = spec.fx
        background.Color = ColorSequence.new(
            Widgets.color(fx.backgroundTopHex),
            Widgets.color(fx.backgroundBottomHex)
        )
        stroke.Color = Widgets.color(fx.frameHex)
        glowStroke.Color = Widgets.color(fx.frameHex)
        glow.Visible = fx.glow

        if spec.imageMode == "swatch" then
            image.Image = ""
            image.BackgroundTransparency = 0
            image.BackgroundColor3 = Widgets.color(spec.swatchHex)
            image.ImageColor3 = Color3.new(1, 1, 1)
        else
            image.Image = spec.imageUrl or ""
            image.BackgroundTransparency = 1
            image.ImageColor3 = if spec.imageTintHex ~= nil
                then Widgets.color(spec.imageTintHex)
                else Color3.new(1, 1, 1)
        end

        lockTag.Visible = spec.locked
        badge.Visible = spec.badge ~= nil
        badge.Text = spec.badge or ""

        shimmer.Visible = fx.shimmer
        if fx.shimmer then
            stopShimmer = RarityShimmer.add(sweep, fx.shimmerPeriodSeconds)
        end
    end

    return {
        root = root,
        apply = apply,
        destroy = function()
            if stopShimmer ~= nil then
                stopShimmer()
                stopShimmer = nil
            end
            root:Destroy()
        end,
    }
end

return ItemIconView
