--!strict
local Config = require("../../../src/shared/Config")
local PriceLabel = require("../../../src/shared/features/pricing/PriceLabel")
local harness = require("../../harness")

-- Config keys that may hold a number named like a price. expectedMonthlyPrice only feeds the
-- release checklist (the platform price is set in Creator Hub) and is never shown in a UI.
local ALLOWED_PRICE_KEYS: { [string]: boolean } = { expectedMonthlyPrice = true }

local function looksLikePrice(key: string): boolean
    local lowered = string.lower(key)
    return string.find(lowered, "price", 1, true) ~= nil
        or string.find(lowered, "robux", 1, true) ~= nil
        or string.find(lowered, "cost", 1, true) ~= nil
end

-- Collects "path.key" for every numeric value stored under a price-like key.
local function findPriceLiterals(value: unknown, path: string, found: { string })
    if type(value) ~= "table" then
        return
    end
    for key, child in value :: { [unknown]: unknown } do
        local name = tostring(key)
        if type(child) == "number" and looksLikePrice(name) and not ALLOWED_PRICE_KEYS[name] then
            table.insert(found, `{path}.{name}`)
        end
        findPriceLiterals(child, `{path}.{name}`, found)
    end
end

return function(suite: harness.Harness)
    suite:test("a plain price shows only the runtime amount", function()
        local label = PriceLabel.format({
            robux = 100,
            baseRobux = 100,
            discountPercent = 0,
            plusDiscount = false,
        })
        harness.equal(label, "100", "plain")
    end)

    suite:test("a Plus discount shows what the player pays and the base price", function()
        local label = PriceLabel.format({
            robux = 90,
            baseRobux = 100,
            discountPercent = 10,
            plusDiscount = true,
        })
        harness.equal(label, "90 (was 100, 10% off with Plus)", "discounted")
    end)

    suite:test("a non-Plus discount does not claim Plus", function()
        local label = PriceLabel.format({
            robux = 80,
            baseRobux = 100,
            discountPercent = 20,
            plusDiscount = false,
        })
        harness.equal(label, "80 (was 100, 20% off)", "other discount")
    end)

    suite:test("Config holds no display price literal (prices are read at runtime)", function()
        local found: { string } = {}
        findPriceLiterals(Config.default, "Config.default", found)
        harness.equal(table.concat(found, ", "), "", "price literals in Config")
    end)

    suite:test("the price-literal scan fails on a config with a hardcoded UI price", function()
        local found: { string } = {}
        findPriceLiterals({ shop = { coinsPriceRobux = 99 } }, "fake", found)
        harness.equal(#found, 1, "the price literal is caught")
    end)
end
