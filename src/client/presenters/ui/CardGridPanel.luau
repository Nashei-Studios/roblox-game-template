--!strict
--[[
    Client presenter: a scrolling grid of cards behind `CardGrid.CardGridPresenter`. One card per
    `CardGrid.Card`: a swatch, the name and a status line. Built from the template Widgets and the
    theme tokens; it paints only the swatch color from the card data and never re-tints a kit.
    A game that has kit cards (a MenuTemplate `Card`) writes its own presenter with the same
    interface instead of using this one. Engine code: excluded from the coverage gate, kept thin.
    UNVERIFIED until a person checks it in Studio's Device Emulator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CardGrid = require(Shared.features.ui.CardGrid)
local ItemIcon = require(Shared.features.ui.ItemIcon)
local RarityConfig = require(Shared.features.rarity.RarityConfig)
local RarityFx = require(Shared.features.rarity.RarityFx)
local UiConfig = require(Shared.features.ui.UiConfig)
local ItemIconView = require(script.Parent.ItemIconView)
local Widgets = require(script.Parent.Widgets)

-- What a card with an `icon` needs; omitted when no card has one.
export type IconDeps = {
    rarity: RarityConfig.Config,
    quality: RarityFx.Quality,
    lockedText: string,
    levelPrefix: string,
}

export type Deps = {
    theme: UiConfig.Theme,
    -- The frame the grid goes in (a menu body).
    parent: Instance,
    cards: { CardGrid.Card },
    labels: CardGrid.StatusLabels,
    -- Minimum card width and height in points.
    minCardWidth: number,
    minCardHeight: number,
    icons: IconDeps?,
}

local CardGridPanel = {}

function CardGridPanel.new(deps: Deps): CardGrid.CardGridPresenter
    local theme = deps.theme
    local gap = theme.spacing.sm
    local scroller = Instance.new("ScrollingFrame")
    scroller.Name = "CardGrid"
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.Size = UDim2.fromScale(1, 1)
    scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroller.CanvasSize = UDim2.fromScale(0, 0)
    scroller.Parent = deps.parent
    local grid = Widgets.grid(scroller, gap)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local function layout()
        local width = scroller.AbsoluteSize.X - scroller.ScrollBarThickness
        local _, cell = CardGrid.columnsFor(width, deps.minCardWidth, gap)
        grid.CellSize = UDim2.fromOffset(math.floor(cell), deps.minCardHeight)
    end
    scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

    type Entry = { card: CardGrid.Card, status: TextLabel, icon: ItemIconView.ItemIconView? }
    local entries: { Entry } = {}
    for order, card in deps.cards do
        local frame = Widgets.panel(scroller, theme, card.id, theme.palette.surface)
        frame.LayoutOrder = order
        local slot: Frame
        local iconView: ItemIconView.ItemIconView? = nil
        if card.icon ~= nil and deps.icons ~= nil then
            local view = ItemIconView.new({
                theme = theme,
                parent = frame,
                name = "Icon",
                lockedText = deps.icons.lockedText,
            })
            slot = view.root
            iconView = view
        else
            slot = Widgets.panel(frame, theme, "Swatch", card.swatchHex)
        end
        slot.AnchorPoint = Vector2.new(0, 0.5)
        slot.Position = UDim2.fromScale(0.03, 0.5)
        slot.Size = UDim2.fromScale(0.28, 0.84)
        local text = Instance.new("Frame")
        text.Name = "Text"
        text.BackgroundTransparency = 1
        text.AnchorPoint = Vector2.new(0, 0.5)
        text.Position = UDim2.fromScale(0.34, 0.5)
        text.Size = UDim2.fromScale(0.62, 0.84)
        text.Parent = frame
        Widgets.stack(text, gap)
        Widgets.label(text, theme, "Name", card.name, "body", theme.palette.textPrimary)
        local status = Widgets.label(text, theme, "Status", "", "caption", theme.palette.textMuted)
        table.insert(entries, { card = card, status = status, icon = iconView })
    end
    layout()

    local presenter: CardGrid.CardGridPresenter = {
        refresh = function(owned: { string })
            for _, entry in entries do
                entry.status.Text = CardGrid.status(entry.card, owned, deps.labels)
                local icons = deps.icons
                if entry.icon ~= nil and entry.card.icon ~= nil and icons ~= nil then
                    entry.icon.apply(
                        ItemIcon.spec(
                            entry.card.icon,
                            { unlocked = table.find(owned, entry.card.id) ~= nil },
                            icons.rarity,
                            icons.quality,
                            theme.palette.surface,
                            icons.levelPrefix
                        )
                    )
                end
            end
        end,
    }
    return presenter
end

return CardGridPanel
