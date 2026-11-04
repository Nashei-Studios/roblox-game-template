--!strict
--[[
    Builds the price text of a UI from a runtime PriceQuote (never from a literal).
    The only way to get a label is to pass a quote read through the PriceLookup port, so a view
    cannot print a hardcoded price by going through this module.
]]

local PriceLookup = require("../../ports/PriceLookup")

local PriceLabel = {}

--- "90" for a plain price, "90 (was 100, 10% off with Plus)" when a discount applies.
function PriceLabel.format(quote: PriceLookup.PriceQuote): string
    if quote.discountPercent <= 0 or quote.baseRobux == quote.robux then
        return `{quote.robux}`
    end
    local reason = if quote.plusDiscount then " with Plus" else ""
    return `{quote.robux} (was {quote.baseRobux}, {quote.discountPercent}% off{reason})`
end

return PriceLabel
