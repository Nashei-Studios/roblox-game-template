--!strict
--[[
    Stack (vertical) and Row (horizontal): a frame that lays its children out in a list with a gap
    taken from a token key. There is no way to build one without a gap: `gap` defaults to the
    token default and a key is the only accepted form, so "items touch" cannot happen.
    Size is automatic on the main axis, so it never clips its children.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tokens = require(Shared.features.uisystem.Tokens)
local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local UiEnv = require(script.Parent.UiEnv)

export type Options = {
    name: string,
    -- Token key of the gap between items. Default: tokens.defaults.gap.
    gap: Tokens.SpacingKey?,
    -- Token key of the padding inside the frame. nil = none (a pure layout box).
    pad: Tokens.SpacingKey?,
    -- Cross-axis alignment of the items.
    align: Enum.HorizontalAlignment | Enum.VerticalAlignment | nil,
}

local Stack = {}

local function build(
    env: UiEnv.UiEnv,
    parent: Instance,
    options: Options,
    horizontal: boolean
): Frame
    local tokens = env.tokens
    local frame = Instance.new("Frame")
    frame.Name = options.name
    frame.BackgroundTransparency = 1
    frame.AutomaticSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
    frame.Size = if horizontal then UDim2.fromScale(0, 1) else UDim2.fromScale(1, 0)
    local list = Atoms.list(frame, tokens, options.gap or tokens.defaults.gap, horizontal)
    local align = options.align
    if align ~= nil then
        if horizontal then
            list.VerticalAlignment = align :: Enum.VerticalAlignment
        else
            list.HorizontalAlignment = align :: Enum.HorizontalAlignment
        end
    end
    if options.pad ~= nil then
        Atoms.pad(frame, tokens, options.pad)
    end
    frame.Parent = parent
    return frame
end

--- A vertical stack. Children get LayoutOrder to order them.
function Stack.vertical(env: UiEnv.UiEnv, parent: Instance, options: Options): Frame
    local frame = build(env, parent, options, false)
    DevGuard.verify(frame, `Stack {options.name}`)
    return frame
end

--- A horizontal row.
function Stack.horizontal(env: UiEnv.UiEnv, parent: Instance, options: Options): Frame
    local frame = build(env, parent, options, true)
    DevGuard.verify(frame, `Row {options.name}`)
    return frame
end

return Stack
