--!strict
--[[
    OfferCard: a limited offer tile for the right HUD rail (title, price line, a buy action and a
    countdown line). It composes Card-level parts only; the price text arrives already formatted
    by PriceLabel (features/pricing), so no Robux literal or price lives here. The buy action is
    a Button, so it keeps the touch floor and the fit rules.
]]

local Atoms = require(script.Parent.Atoms)
local Button = require(script.Parent.Button)
local DevGuard = require(script.Parent.DevGuard)
local Parts = require(script.Parent.Parts)
local Stack = require(script.Parent.Stack)
local UiEnv = require(script.Parent.UiEnv)

export type Options = {
    name: string,
    title: string,
    -- Price line, formatted by the pricing feature (for example the output of PriceLabel).
    priceText: string,
    buyText: string,
    onBuy: () -> (),
}

export type OfferCard = {
    root: Frame,
    -- Sets the countdown line ("" hides it).
    setCountdown: (self: OfferCard, text: string) -> (),
    -- Disables the buy action while a purchase is pending.
    setBusy: (self: OfferCard, busy: boolean) -> (),
}

local OfferCard = {}

function OfferCard.new(env: UiEnv.UiEnv, parent: Instance, options: Options): OfferCard
    local tokens = env.tokens
    local root = Atoms.panel(parent, tokens, options.name, "surface", "md")
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.Size = UDim2.fromOffset(tokens.touchMin * 3, 0)
    Atoms.pad(root, tokens, tokens.defaults.cardPad)
    local column = Stack.vertical(env, root, { name = "Content" })
    Atoms.label(column, tokens, "Title", options.title, "body", tokens.palette.textPrimary, 1)
    Atoms.label(column, tokens, "Price", options.priceText, "caption", Parts.hex(env, "warning"), 1)
    local countdown =
        Atoms.label(column, tokens, "Countdown", "", "caption", tokens.palette.textMuted, 1)
    countdown.Visible = false
    local buy = Button.new(env, column, {
        name = "Buy",
        text = options.buyText,
        onActivated = options.onBuy,
    })
    local self = {} :: OfferCard
    self.root = root
    function self.setCountdown(_self: OfferCard, text: string)
        countdown.Text = text
        countdown.Visible = text ~= ""
    end
    function self.setBusy(_self: OfferCard, busy: boolean)
        Button.setEnabled(buy, env, not busy)
    end
    DevGuard.verify(root, `OfferCard {options.name}`)
    return self
end

return OfferCard
