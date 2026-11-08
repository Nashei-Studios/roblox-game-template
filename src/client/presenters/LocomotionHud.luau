--!strict
--[[
    Client presenter: the sprint and equip buttons of the locomotion HUD, built with the UI
    system Button (ADR 0035), never raw Frames. They are stacked at the bottom right of the HUD
    content frame, 44 px minimum by the touch floor. Text comes from the caller (localisation
    and game vocabulary are not decided here). Excluded from the coverage gate; the visual check
    is a UI Labs story or a Studio playtest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tokens = require(ReplicatedStorage.Shared.features.uisystem.Tokens)
local Button = require(script.Parent.ui.system.Button)
local Stack = require(script.Parent.ui.system.Stack)
local UiEnv = require(script.Parent.ui.system.UiEnv)

export type Options = {
    sprintText: string,
    equipText: string,
    onSprint: (began: boolean) -> (),
    onEquipToggle: () -> (),
}

local LocomotionHud = {}

--- Builds the buttons inside `parent` (the SafeAreaRoot content frame). Returns the holder.
function LocomotionHud.mount(env: UiEnv.UiEnv, parent: Instance, options: Options): Instance
    local column = Stack.vertical(env, parent, { name = "LocomotionHud", gap = "sm" })
    column.AnchorPoint = Vector2.new(1, 1)
    column.Position = UDim2.fromScale(1, 1)
    column.Size = UDim2.fromOffset(
        env.tokens.touchMin * 3,
        env.tokens.touchMin * 2 + Tokens.space(env.tokens, "sm")
    )
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
    Button.new(env, column, {
        name = "Equip",
        text = options.equipText,
        variant = "primary",
        onActivated = options.onEquipToggle,
    })
    return column
end

return LocomotionHud
