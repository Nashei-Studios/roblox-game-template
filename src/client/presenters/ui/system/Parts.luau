--!strict
--[[
    Parts: small components that need no kit piece: Badge, CurrencyChip, ProgressBar, Tabs, Tooltip.
    Each takes the environment, builds from tokens, audits itself in dev mode and returns a small
    handle. Colors are palette KEYS (type-checked), never hex literals.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SafeArea = require(Shared.features.uisystem.SafeArea)
local Atoms = require(script.Parent.Atoms)
local Button = require(script.Parent.Button)
local DevGuard = require(script.Parent.DevGuard)
local Stack = require(script.Parent.Stack)
local UiEnv = require(script.Parent.UiEnv)

export type Tone = "accent" | "success" | "warning" | "danger"

local Parts = {}

--- Hex of a palette key. One cast, here, so call sites stay typed by key.
function Parts.hex(env: UiEnv.UiEnv, key: string): string
    return Atoms.hex(env.tokens, key)
end

-- Badge ---------------------------------------------------------------------------------------

export type Badge = { root: Frame, set: (self: Badge, count: number) -> () }

--- A notification dot / count in the top-right corner of `target` (a HUD tile). 0 hides it.
function Parts.badge(env: UiEnv.UiEnv, target: GuiObject, tone: Tone): Badge
    local tokens = env.tokens
    local edge = math.max(tokens.type.caption + tokens.spacing.xs, tokens.spacing.lg)
    local root = Atoms.panel(target, tokens, "Badge", Parts.hex(env, tone), "lg")
    root.AnchorPoint = Vector2.new(1, 0)
    root.Position = UDim2.fromScale(1, 0)
    root.Size = UDim2.fromOffset(edge, edge)
    root.ZIndex = target.ZIndex + 1
    root.Visible = false
    local label = Atoms.label(root, tokens, "Count", "", "caption", tokens.palette.onAccent, 1)
    label.Size = UDim2.fromScale(1, 1)
    label.TextXAlignment = Enum.TextXAlignment.Center
    local self = {} :: Badge
    self.root = root
    function self.set(_self: Badge, count: number)
        root.Visible = count > 0
        label.Text = if count > 99 then "99+" elseif count > 0 then tostring(count) else ""
    end
    return self
end

-- CurrencyChip --------------------------------------------------------------------------------

export type CurrencyChip = { root: Frame, set: (self: CurrencyChip, text: string) -> () }

--- An icon and an amount in a pill. The amount text is formatted by the caller (NumberFormat).
function Parts.currencyChip(
    env: UiEnv.UiEnv,
    parent: Instance,
    name: string,
    icon: string?
): CurrencyChip
    local tokens = env.tokens
    local root = Atoms.panel(parent, tokens, name, "surfaceRaised", "lg")
    root.AutomaticSize = Enum.AutomaticSize.X
    root.Size = UDim2.fromOffset(0, tokens.touchMin)
    Atoms.pad(root, tokens, "sm")
    local row = Stack.horizontal(
        env,
        root,
        { name = "Row", gap = "xs", align = Enum.VerticalAlignment.Center }
    )
    row.Size = UDim2.fromOffset(0, tokens.touchMin - 2 * tokens.spacing.sm)
    if icon ~= nil then
        local image = Instance.new("ImageLabel")
        image.Name = "Icon"
        image.BackgroundTransparency = 1
        image.Image = icon
        image.Size = UDim2.fromOffset(tokens.type.title, tokens.type.title)
        image.Parent = row
    end
    local amount = Atoms.label(row, tokens, "Amount", "0", "body", tokens.palette.textPrimary, 1)
    amount.AutomaticSize = Enum.AutomaticSize.None
    amount.Size = UDim2.fromOffset(tokens.type.body * 6, tokens.type.body * 1.6)
    local self = {} :: CurrencyChip
    self.root = root
    function self.set(_self: CurrencyChip, text: string)
        amount.Text = text
    end
    DevGuard.verify(root, `CurrencyChip {name}`)
    return self
end

-- ProgressBar ---------------------------------------------------------------------------------

export type ProgressBar = { root: Frame, set: (self: ProgressBar, fraction: number) -> () }

--- A track and a fill. `set` clamps to 0..1 so a bad number never draws outside the track.
function Parts.progressBar(
    env: UiEnv.UiEnv,
    parent: Instance,
    name: string,
    tone: Tone
): ProgressBar
    local tokens = env.tokens
    local track = Atoms.panel(parent, tokens, name, "surfaceRaised", "sm")
    track.Size = UDim2.new(1, 0, 0, tokens.spacing.md)
    track.ClipsDescendants = true
    local fill = Atoms.panel(track, tokens, "Fill", Parts.hex(env, tone), "sm")
    fill.Size = UDim2.fromScale(0, 1)
    local self = {} :: ProgressBar
    self.root = track
    function self.set(_self: ProgressBar, fraction: number)
        local value = if fraction ~= fraction then 0 else math.clamp(fraction, 0, 1)
        fill.Size = UDim2.fromScale(value, 1)
    end
    return self
end

-- Tabs ----------------------------------------------------------------------------------------

export type Tab = { id: string, label: string }
export type Tabs = { root: Frame, select: (self: Tabs, id: string) -> () }

--- A row of equal tab buttons (each at least the touch floor). `onSelect` runs on a change.
function Parts.tabs(
    env: UiEnv.UiEnv,
    parent: Instance,
    tabs: { Tab },
    onSelect: (id: string) -> ()
): Tabs
    local tokens = env.tokens
    local row = Stack.horizontal(env, parent, { name = "Tabs", gap = "xs" })
    row.Size = UDim2.new(1, 0, 0, tokens.touchMin)
    row.AutomaticSize = Enum.AutomaticSize.None
    local buttons: { [string]: TextButton } = {}
    local function choose(id: string)
        for tabId, button in buttons do
            local active = tabId == id
            button.BackgroundColor3 =
                Atoms.color(if active then tokens.palette.accent else tokens.palette.surfaceRaised)
            button.TextColor3 =
                Atoms.color(if active then tokens.palette.onAccent else tokens.palette.textMuted)
        end
    end
    local count = math.max(#tabs, 1)
    for index, tab in tabs do
        local button = Button.new(env, row, {
            name = `Tab_{tab.id}`,
            text = tab.label,
            variant = "secondary",
            onActivated = function()
                choose(tab.id)
                onSelect(tab.id)
            end,
        })
        -- Equal share of the row minus the gaps, never below the touch floor (UISizeConstraint).
        button.Size = UDim2.new(1 / count, -tokens.spacing.xs, 1, 0)
        button.LayoutOrder = index
        buttons[tab.id] = button
    end
    if tabs[1] ~= nil then
        choose(tabs[1].id)
    end
    local self = {} :: Tabs
    self.root = row
    function self.select(_self: Tabs, id: string)
        choose(id)
    end
    DevGuard.verify(row, "Tabs")
    return self
end

-- Tooltip -------------------------------------------------------------------------------------

export type Tooltip = {
    root: Frame,
    -- Shows `text` next to a target rect (screen px), kept inside the usable area.
    showAt: (self: Tooltip, text: string, anchor: SafeArea.Rect) -> (),
    hide: (self: Tooltip) -> (),
}

--- A tooltip on the overlay layer. Placed above the anchor when there is room, else below, and
--- pulled back inside the usable area so it is never cut off.
function Parts.tooltip(env: UiEnv.UiEnv, overlay: Instance): Tooltip
    local tokens = env.tokens
    local root = Atoms.panel(overlay, tokens, "Tooltip", "surfaceRaised", "md")
    root.AutomaticSize = Enum.AutomaticSize.XY
    root.Visible = false
    root.ZIndex = 10
    Atoms.pad(root, tokens, "sm")
    local label = Atoms.label(root, tokens, "Text", "", "caption", tokens.palette.textPrimary, 1)
    label.AutomaticSize = Enum.AutomaticSize.None
    label.Size = UDim2.fromOffset(tokens.type.caption * 12, tokens.type.caption * 1.6)
    local self = {} :: Tooltip
    self.root = root
    function self.showAt(_self: Tooltip, text: string, anchor: SafeArea.Rect)
        label.Text = text
        local width = label.Size.X.Offset + 2 * tokens.spacing.sm
        local height = label.Size.Y.Offset + 2 * tokens.spacing.sm
        local gap = tokens.spacing.xs
        local above = anchor.y - height - gap >= env.usable.y
        local rect: SafeArea.Rect = {
            x = anchor.x + (anchor.width - width) / 2,
            y = if above then anchor.y - height - gap else anchor.y + anchor.height + gap,
            width = width,
            height = height,
        }
        local dx, dy = SafeArea.clampOffset(env.usable, rect)
        root.AnchorPoint = Vector2.zero
        root.Position = UDim2.fromOffset(rect.x + dx - env.usable.x, rect.y + dy - env.usable.y)
        root.Visible = true
    end
    function self.hide(_self: Tooltip)
        root.Visible = false
    end
    return self
end

return Parts
