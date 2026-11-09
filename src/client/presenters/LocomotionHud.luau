--!strict
--[[
    Client presenter: the sprint and equip buttons of the locomotion HUD, built with the UI
    system Button (ADR 0035), never raw Frames. They are touch-only (ControlRegistry, ADR 0045): on keyboard and gamepad each is replaced by a
    key hint built from the configured keys, and the swap follows the input scheme live. They are
    stacked at the bottom right of the HUD
    content frame, 44 px minimum by the touch floor. Text comes from the caller (localisation
    and game vocabulary are not decided here). Excluded from the coverage gate; the visual check
    is a UI Labs story or a Studio playtest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ControlRegistry = require(Shared.features.ui.ControlRegistry)
local Tokens = require(Shared.features.uisystem.Tokens)
local Atoms = require(script.Parent.ui.system.Atoms)
local Button = require(script.Parent.ui.system.Button)
local InputSchemeWatcher = require(script.Parent.ui.InputSchemeWatcher)
local Stack = require(script.Parent.ui.system.Stack)
local UiEnv = require(script.Parent.ui.system.UiEnv)

export type Options = {
    sprintText: string,
    equipText: string,
    onSprint: (began: boolean) -> (),
    onEquipToggle: () -> (),
    -- Filled by LocomotionControls.register; the HUD asks it who is shown on which scheme.
    registry: ControlRegistry.Registry,
    watcher: InputSchemeWatcher.Watcher,
}

local LocomotionHud = {}

--- Builds the buttons inside `parent` (the SafeAreaRoot content frame). Returns the holder.
function LocomotionHud.mount(env: UiEnv.UiEnv, parent: Instance, options: Options): Instance
    local tokens = env.tokens
    local column = Stack.vertical(env, parent, { name = "LocomotionHud", gap = "sm" })
    column.AnchorPoint = Vector2.new(1, 1)
    column.Position = UDim2.fromScale(1, 1)
    column.Size =
        UDim2.fromOffset(tokens.touchMin * 3, tokens.touchMin * 2 + Tokens.space(tokens, "sm"))
    local sprint = Button.new(env, column, {
        name = "Sprint",
        text = options.sprintText,
        variant = "secondary",
        onActivated = function() end,
    })
    -- Hold to run: the button reports began on press and ended on release.
    sprint.InputBegan:Connect(function(input: InputObject)
        if
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            options.onSprint(true)
        end
    end)
    sprint.InputEnded:Connect(function(input: InputObject)
        if
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            options.onSprint(false)
        end
    end)
    local equip = Button.new(env, column, {
        name = "Equip",
        text = options.equipText,
        variant = "primary",
        onActivated = options.onEquipToggle,
    })
    local hints: { [string]: TextLabel } = {}
    for _, entry in
        {
            { id = "Sprint", text = options.sprintText, order = 1 },
            { id = "Equip", text = options.equipText, order = 2 },
        }
    do
        local hint = Atoms.label(
            column,
            tokens,
            `{entry.id}Hint`,
            "",
            "caption",
            tokens.palette.textMuted,
            1
        )
        hint.LayoutOrder = entry.order
        hint.TextXAlignment = Enum.TextXAlignment.Right
        hints[entry.id] = hint
    end
    sprint.LayoutOrder = 1
    equip.LayoutOrder = 2
    local buttons: { [string]: TextButton } = { Sprint = sprint, Equip = equip }
    local texts: { [string]: string } = { Sprint = options.sprintText, Equip = options.equipText }
    -- Live: a button only exists on the schemes that need it, a key hint on the others.
    options.watcher.subscribe(function(scheme: string)
        for id, button in buttons do
            local shown = ControlRegistry.visibleOn(options.registry, id, scheme)
            button.Visible = shown
            local hintText = ControlRegistry.hintFor(options.registry, id, scheme)
            local hint = hints[id]
            hint.Visible = not shown and hintText ~= nil
            hint.Text = if hintText ~= nil then `{texts[id]}: {hintText}` else ""
        end
    end)
    return column
end

return LocomotionHud
