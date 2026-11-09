--!strict
--[[
    Button: the plain button, in four variants taken from the palette tokens. A kit supplies the
    HUD buttons and the menu rows (HudRailsView, Card); this is the one for everything the kit has
    no piece for (confirm, retry, tabs). It is never smaller than the touch floor, its text always
    fits, it answers press (and hover on desktop) with the UiMotion presets, and it activates on touch, click and gamepad (Activated covers all of them).
]]

local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local UiEnv = require(script.Parent.UiEnv)
local UiMotionPlayer = require(script.Parent.UiMotionPlayer)

-- One of primary, secondary, danger, ghost (a plain string: the stable solver widens unions).
export type Variant = string

export type Options = {
    name: string,
    text: string,
    variant: Variant?,
    onActivated: () -> (),
    -- Width in px; nil = fill the parent width.
    width: number?,
}

local FILL: { [string]: string } = {
    primary = "accent",
    secondary = "surfaceRaised",
    danger = "danger",
    ghost = "surface",
}
local TEXT: { [string]: string } = {
    primary = "onAccent",
    secondary = "textPrimary",
    danger = "textPrimary",
    ghost = "textMuted",
}

local Button = {}

--- Greys a button out and stops it from reacting.
function Button.setEnabled(button: TextButton, env: UiEnv.UiEnv, enabled: boolean)
    local palette = env.tokens.palette
    button.Active = enabled
    button.AutoButtonColor = enabled
    button.BackgroundColor3 = Atoms.color(if enabled then palette.accent else palette.surfaceRaised)
    button.TextColor3 = Atoms.color(if enabled then palette.onAccent else palette.textMuted)
end

function Button.new(env: UiEnv.UiEnv, parent: Instance, options: Options): TextButton
    local tokens = env.tokens
    local variant: Variant = options.variant or "primary"
    assert(FILL[variant] ~= nil, `unknown button variant "{variant}"`)
    local button = Instance.new("TextButton")
    button.Name = options.name
    button.AutoButtonColor = true
    button.Font = Atoms.font(tokens.font)
    button.Text = options.text
    button.TextColor3 = Atoms.color(Atoms.hex(tokens, TEXT[variant]))
    button.BackgroundColor3 = Atoms.color(Atoms.hex(tokens, FILL[variant]))
    button.BorderSizePixel = 0
    local width = options.width
    button.Size = if width ~= nil
        then UDim2.fromOffset(math.max(width, tokens.touchMin), tokens.touchMin)
        else UDim2.new(1, 0, 0, tokens.touchMin)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, tokens.radius.md)
    corner.Parent = button
    Atoms.pad(button, tokens, "sm")
    Atoms.fitText(button, tokens, tokens.type.body)
    Atoms.touchFloor(button, tokens)
    button.Activated:Connect(options.onActivated)
    -- Press feedback everywhere; hover only with a pointer (docs/adr/0063, spec section 6).
    UiMotionPlayer.bindButton(button, env.reducedMotion, env.deviceClass == "desktop")
    button.Parent = parent
    DevGuard.verify(button, `Button {options.name}`)
    return button
end

return Button
