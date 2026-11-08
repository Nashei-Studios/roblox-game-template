--!strict
--[[
    Pure model of a grid of cards (a wardrobe, a collection, an index): the card data, the status
    line each card shows from what the player owns, and the presenter interface a menu talks to.
    Loads under Lune. The engine side is `client/presenters/ui/CardGridPanel`; a game with its own
    kit cards implements `CardGridPresenter` over them and keeps the same model.
]]

export type Card = {
    id: string,
    name: string,
    -- Swatch color "#RRGGBB"; the panel paints only this, never the kit.
    swatchHex: string,
    -- False while the card cannot be obtained yet (for example its pass id is still nil).
    obtainable: boolean,
}

export type StatusLabels = { owned: string, available: string, unavailable: string }

-- What a menu calls; the shell behind it can change without touching the data.
export type CardGridPresenter = {
    -- Repaints every card from the ids the player owns.
    refresh: (owned: { string }) -> (),
}

local CardGrid = {}

--- The status line of one card: owned wins, then obtainable, else unavailable.
function CardGrid.status(card: Card, owned: { string }, labels: StatusLabels): string
    if table.find(owned, card.id) ~= nil then
        return labels.owned
    end
    if card.obtainable then
        return labels.available
    end
    return labels.unavailable
end

--- One problem per invalid card list (empty when valid): ids unique and non-empty, "#RRGGBB".
function CardGrid.validate(cards: { Card }): { string }
    local problems: { string } = {}
    local seen: { [string]: boolean } = {}
    for index, card in cards do
        if card.id == "" then
            table.insert(problems, `card {index} has no id`)
        elseif seen[card.id] then
            table.insert(problems, `card id "{card.id}" is repeated`)
        end
        seen[card.id] = true
        if string.match(card.swatchHex, "^#%x%x%x%x%x%x$") == nil then
            table.insert(problems, `card "{card.id}" swatch must be #RRGGBB`)
        end
    end
    return problems
end

--- Columns and cell width for a grid. Never 0 columns: one column only when two cards of
--- `minCardWidth` do not fit in `available`. The cells share the leftover width evenly.
function CardGrid.columnsFor(available: number, minCardWidth: number, gap: number): (number, number)
    local width = math.max(available, 0)
    local card = math.max(minCardWidth, 1)
    local columns = math.max(1, math.floor((width + gap) / (card + gap)))
    local cell = (width - gap * (columns - 1)) / columns
    return columns, math.max(cell, 0)
end

return CardGrid
