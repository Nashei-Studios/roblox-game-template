--!strict
--[[
    Card: one menu row with a name, a description and an action. Kit-skinned from the
    "menu.rowCard" slot (Studded native: the row is cloned and only its texts and the action are
    bound, never re-tinted); plain panel from the tokens when the kit has no such piece.
]]

local Atoms = require(script.Parent.Atoms)
local Button = require(script.Parent.Button)
local DevGuard = require(script.Parent.DevGuard)
local Stack = require(script.Parent.Stack)
local UiEnv = require(script.Parent.UiEnv)

export type Options = {
    name: string,
    title: string,
    description: string,
    actionText: string,
    onAction: () -> (),
}

export type Card = {
    root: GuiObject,
    action: TextButton | GuiButton,
    setAction: (self: Card, text: string, enabled: boolean) -> (),
}

local Card = {}

function Card.new(env: UiEnv.UiEnv, parent: Instance, options: Options): Card
    local tokens = env.tokens
    local piece = env.skin:cloneSlot("menu.rowCard")
    local self = {} :: Card
    if piece ~= nil and piece:IsA("GuiObject") then
        local nameLabel = env.skin:part(piece, "menu.rowCard", "name") :: TextLabel
        local descLabel = env.skin:part(piece, "menu.rowCard", "description") :: TextLabel
        local action = env.skin:part(piece, "menu.rowCard", "action") :: TextButton
        nameLabel.Text = options.title
        descLabel.Text = options.description
        local actionLabel = action:FindFirstChildOfClass("TextLabel")
        if actionLabel ~= nil then
            actionLabel.Text = options.actionText
        end
        action.Activated:Connect(options.onAction)
        piece.Name = options.name
        piece.Parent = parent
        self.root = piece
        self.action = action
        function self.setAction(_self: Card, text: string, enabled: boolean)
            if actionLabel ~= nil then
                actionLabel.Text = text
            end
            action.Active = enabled
            action.AutoButtonColor = enabled
        end
    else
        local frame = Atoms.panel(parent, tokens, options.name, "surface", "md")
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.Size = UDim2.fromScale(1, 0)
        Atoms.pad(frame, tokens, tokens.defaults.cardPad)
        local column = Stack.vertical(env, frame, { name = "Content" })
        Atoms.label(column, tokens, "Title", options.title, "title", tokens.palette.textPrimary, 1)
        Atoms.label(
            column,
            tokens,
            "Description",
            options.description,
            "body",
            tokens.palette.textMuted,
            2
        )
        local action = Button.new(env, column, {
            name = "Action",
            text = options.actionText,
            onActivated = options.onAction,
        })
        self.root = frame
        self.action = action
        function self.setAction(_self: Card, text: string, enabled: boolean)
            action.Text = text
            Button.setEnabled(action, env, enabled)
        end
    end
    DevGuard.verify(self.root, `Card {options.name}`)
    return self
end

return Card
