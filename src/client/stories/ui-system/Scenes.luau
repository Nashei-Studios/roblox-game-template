--!strict
--[[
    The three scenes the stories render at each review viewport: the HUD rails, a menu with a
    list and a grid, and the small components. Strings here are story-only placeholders (a game
    passes its own through Config); no gameplay value lives in a story.
]]

local System = script.Parent.Parent.Parent.presenters.ui.system
local Button = require(System.Button)
local Card = require(System.Card)
local HudRailsView = require(System.HudRailsView)
local MenuShell = require(System.MenuShell)
local OfferCard = require(System.OfferCard)
local Parts = require(System.Parts)
local SafeAreaRoot = require(System.SafeAreaRoot)
local ScrollList = require(System.ScrollList)
local Stack = require(System.Stack)
local Toast = require(System.Toast)
local UiEnv = require(System.UiEnv)

local Scenes = {}

local function noop() end

--- Left 4, right 3 (two of them offers), bottom 4: the busiest HUD a game ships.
function Scenes.hud(env: UiEnv.UiEnv, root: SafeAreaRoot.Root)
    local specs: { HudRailsView.TileSpec } = {}
    for index = 1, 4 do
        table.insert(specs, { id = `L{index}`, icon = nil, rail = "left", onActivated = noop })
    end
    for index = 1, 3 do
        table.insert(specs, { id = `R{index}`, icon = nil, rail = "right", onActivated = noop })
    end
    for index = 1, 4 do
        table.insert(specs, { id = `B{index}`, icon = nil, rail = "bottom", onActivated = noop })
    end
    local view = HudRailsView.new(env, root.content, specs)
    local badge = Parts.badge(env, view.tiles[1].root, "danger")
    badge:set(3)
    local chip = Parts.currencyChip(env, root.overlay, "Coins", nil)
    chip.root.Position = UDim2.fromScale(0.5, 0)
    chip.root.AnchorPoint = Vector2.new(0.5, 0)
    chip:set("1.25K")
end

--- A modal with tabs, a list of cards and a grid, the shape of a shop.
function Scenes.menu(env: UiEnv.UiEnv, root: SafeAreaRoot.Root)
    local shell = MenuShell.new(env, root.content, {
        id = "shop",
        title = "Shop",
        kind = "standard",
        onClose = noop,
    })
    local body = shell.body
    local column = Stack.vertical(env, body, { name = "Column", pad = "sm" })
    column.Size = UDim2.fromScale(1, 1)
    column.AutomaticSize = Enum.AutomaticSize.None
    Parts.tabs(env, column, {
        { id = "items", label = "Items" },
        { id = "boosts", label = "Boosts" },
    }, noop)
    local list = ScrollList.new(env, column, { name = "Rows" })
    list.Size = UDim2.new(1, 0, 1, -env.tokens.touchMin)
    for index = 1, 4 do
        Card.new(env, list, {
            name = `Row{index}`,
            title = `Item {index}`,
            description = "A short description that may wrap onto a second line.",
            actionText = "Buy",
            onAction = noop,
        })
    end
    shell:setVisible(true)
    local progress = Parts.progressBar(env, root.overlay, "Progress", "success")
    progress.root.AnchorPoint = Vector2.new(0.5, 1)
    progress.root.Position = UDim2.fromScale(0.5, 1)
    progress.root.Size = UDim2.new(0.3, 0, 0, env.tokens.spacing.md)
    progress:set(0.6)
end

--- The small components on one board, on the plain skin.
function Scenes.components(env: UiEnv.UiEnv, root: SafeAreaRoot.Root)
    local board = Stack.vertical(env, root.content, { name = "Board", gap = "md" })
    board.Size = UDim2.fromScale(0.5, 1)
    board.AutomaticSize = Enum.AutomaticSize.None
    local variants: { Button.Variant } = { "primary", "secondary", "danger", "ghost" }
    for index = 1, #variants do
        local variant = variants[index]
        Button.new(
            env,
            board,
            { name = variant, text = variant, variant = variant, onActivated = noop }
        )
    end
    local offer = OfferCard.new(env, root.content, {
        name = "Offer",
        title = "Starter pack",
        priceText = "R$ --",
        buyText = "Buy",
        onBuy = noop,
    })
    offer.root.AnchorPoint = Vector2.new(1, 0)
    offer.root.Position = UDim2.fromScale(1, 0)
    offer:setCountdown("01:59:00")
    local toasts = Toast.host(env, root.overlay)
    toasts:show({
        id = 1,
        kind = "reward",
        text = "You got a reward",
        style = "success",
        durationSeconds = 4,
    })
    local tooltip = Parts.tooltip(env, root.overlay)
    tooltip:showAt(
        "Settings",
        { x = env.usable.x, y = env.usable.y + 120, width = 44, height = 44 }
    )
end

return Scenes
