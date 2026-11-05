--!strict
--[[
    The rows of the shop. Pure: loads under Lune. A price is text built from a PriceQuote read at
    runtime (PriceLabel); Config holds no display price. While the quote is pending or failed the
    row shows the configured placeholder and cannot be bought, so a wrong number is never shown.
]]

local PriceLabel = require("../pricing/PriceLabel")
local PriceLookup = require("../../ports/PriceLookup")

export type Product = { name: string, id: number? }

export type QuoteState =
    { status: "pending" }
    | { status: "failed" }
    | { status: "ready", quote: PriceLookup.PriceQuote }

export type Row = {
    productName: string,
    priceText: string,
    canBuy: boolean,
}

export type Placeholders = { pending: string, unavailable: string }

local ShopModel = {}

--- A quote from the two prices a client can read (PriceInRobux and UserBasePriceInRobux).
function ShopModel.quoteFromPrices(robux: number, baseRobux: number?): PriceLookup.PriceQuote
    local base = baseRobux or robux
    local discount = 0
    if base > robux and base > 0 then
        discount = math.floor((base - robux) / base * 100 + 0.5)
    end
    return { robux = robux, baseRobux = base, discountPercent = discount, plusDiscount = false }
end

--- One row per product, in Config order. `states` is keyed by product name.
function ShopModel.rows(
    products: { Product },
    states: { [string]: QuoteState },
    placeholders: Placeholders
): { Row }
    local rows: { Row } = {}
    for _, product in products do
        local state = states[product.name]
        local row: Row
        if product.id == nil or (state ~= nil and state.status == "failed") then
            row =
                { productName = product.name, priceText = placeholders.unavailable, canBuy = false }
        elseif state ~= nil and state.status == "ready" then
            row = {
                productName = product.name,
                priceText = PriceLabel.format(state.quote),
                canBuy = true,
            }
        else
            row = { productName = product.name, priceText = placeholders.pending, canBuy = false }
        end
        table.insert(rows, row)
    end
    return rows
end

return ShopModel
