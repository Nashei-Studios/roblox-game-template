--!strict
local CardGrid = require("../../../src/shared/features/ui/CardGrid")
local harness = require("../../harness")

local LABELS: CardGrid.StatusLabels =
    { owned = "Owned", available = "Available", unavailable = "Coming soon" }

local CARDS: { CardGrid.Card } = {
    { id = "a", name = "A", swatchHex = "#112233", obtainable = true },
    { id = "b", name = "B", swatchHex = "#445566", obtainable = false },
}

return function(suite: harness.Harness)
    suite:test("a card is owned first, then available, else unavailable", function()
        harness.equal(CardGrid.status(CARDS[1], { "a" }, LABELS), "Owned", "owned")
        harness.equal(CardGrid.status(CARDS[1], {}, LABELS), "Available", "available")
        harness.equal(CardGrid.status(CARDS[2], {}, LABELS), "Coming soon", "unavailable")
        harness.equal(CardGrid.status(CARDS[2], { "b" }, LABELS), "Owned", "owned wins")
    end)

    suite:test("cards are validated", function()
        harness.equal(#CardGrid.validate(CARDS), 0, "valid")
        local bad: { CardGrid.Card } = {
            { id = "", name = "X", swatchHex = "#000000", obtainable = true },
            { id = "d", name = "D", swatchHex = "blue", obtainable = true },
            { id = "d", name = "D2", swatchHex = "#000000", obtainable = true },
        }
        harness.equal(#CardGrid.validate(bad), 3, "empty id, bad color, repeated id")
    end)

    suite:test("columns never reach zero and cells share the width", function()
        local columns, cell = CardGrid.columnsFor(400, 190, 8)
        harness.equal(columns, 2, "two columns")
        harness.equal(cell, 196, "even cells")
        local one = CardGrid.columnsFor(150, 190, 8)
        harness.equal(one, 1, "narrow gives one column")
        local zero, width = CardGrid.columnsFor(-5, 190, 8)
        harness.equal(zero, 1, "negative width")
        harness.equal(width, 0, "no negative cell")
    end)
end
