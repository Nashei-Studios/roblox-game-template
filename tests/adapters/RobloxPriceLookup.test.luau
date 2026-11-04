--!strict
local RobloxPriceLookup = require("../../src/server/adapters/RobloxPriceLookup")
local harness = require("../harness")

local function newLookup(info: RobloxPriceLookup.ProductInfoLike?, rows: { { [string]: unknown } }?)
    local requested: { string } = {}
    local lookup = RobloxPriceLookup.new({
        marketplace = {
            GetProductInfoAsync = function(
                _self: unknown,
                id: number,
                infoTypeName: string
            ): RobloxPriceLookup.ProductInfoLike
                table.insert(requested, `{id}:{infoTypeName}`)
                if info == nil then
                    error("no such item")
                end
                return info
            end,
            ListDeveloperProducts = function(_self: unknown): { { [string]: unknown } }
                if rows == nil then
                    error("offline")
                end
                return rows
            end,
        },
    })
    return lookup, requested
end

return function(suite: harness.Harness)
    suite:test("a Plus discount is read from the platform, not computed", function()
        local lookup, requested = newLookup({
            PriceInRobux = 90,
            UserBasePriceInRobux = 100,
            PriceDiscountDetails = { { Type = "RobloxPlusSubscription", Percent = 10 } },
        }, nil)
        local result = lookup:quote("product", 11)
        harness.equal(requested[1], "11:Product", "info type")
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.robux, 90, "paid")
            harness.equal(result.value.baseRobux, 100, "base")
            harness.equal(result.value.discountPercent, 10, "percent")
            harness.isTrue(result.value.plusDiscount, "plus")
        end
    end)

    suite:test("a game pass uses the GamePass info type and no discount means none", function()
        local lookup, requested = newLookup({ PriceInRobux = 50 }, nil)
        local result = lookup:quote("gamePass", 5)
        harness.equal(requested[1], "5:GamePass", "info type")
        harness.isTrue(result.ok and result.value.discountPercent == 0, "no discount")
    end)

    suite:test("an item not for sale and an engine error are typed failures", function()
        local free = newLookup({ PriceInRobux = nil }, nil)
        harness.isFalse(free:quote("product", 1).ok, "not for sale")
        local broken = newLookup(nil, nil)
        local result = broken:quote("product", 1)
        harness.isFalse(result.ok, "engine error")
        if not result.ok then
            harness.isTrue(
                string.find(result.error.message, "no such item", 1, true) ~= nil,
                "message"
            )
        end
    end)

    suite:test("listProducts reads ProductId and PriceInRobux from every row", function()
        local rows: { { [string]: unknown } } = {
            { ProductId = 1, PriceInRobux = 25 },
            { ProductId = 2, PriceInRobux = 75 },
        }
        local lookup = newLookup(nil, rows)
        local result = lookup:listProducts()
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(#result.value, 2, "rows")
            harness.equal(result.value[2].quote.robux, 75, "price")
        end
    end)

    suite:test(
        "a row without the expected fields fails loudly instead of showing a wrong price",
        function()
            local malformed: { { [string]: unknown } } = { { Name = "Coins" } }
            local lookup = newLookup(nil, malformed)
            harness.isFalse(lookup:listProducts().ok, "malformed row")
            local offline = newLookup(nil, nil)
            harness.isFalse(offline:listProducts().ok, "engine error")
        end
    )
end
