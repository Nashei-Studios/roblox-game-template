--!strict
--[[
    Adapter: PriceLookup over MarketplaceService:GetProductInfoAsync and
    MarketplaceService:GetDeveloperProductsAsync. Engine pieces are injected (ADR 0009).
    `GetProductInfoAsync` is wired in Main.server to take the Enum.InfoType item NAME ("Product"
    or "GamePass"). `ListDeveloperProducts` returns the rows of every page as plain dictionaries.
    UNVERIFIED: the docs do not list the field names of a GetDeveloperProductsAsync row; this
    adapter reads ProductId and PriceInRobux and reports a typed error when they are missing, so
    a wrong guess fails loudly instead of showing a wrong price.
]]

-- Structurally identical to ports/PriceLookup.luau (local so this file loads under Lune).
type PriceKind = "product" | "gamePass"
type PriceQuote = {
    robux: number,
    baseRobux: number,
    discountPercent: number,
    plusDiscount: boolean,
}
type ProductQuote = { productId: number, quote: PriceQuote }
type PriceError = { kind: "price_failed", message: string }
type PriceLookup = {
    quote: (
        self: PriceLookup,
        kind: PriceKind,
        id: number
    ) -> { ok: true, value: PriceQuote } | { ok: false, error: PriceError },
    listProducts: (
        self: PriceLookup
    ) -> { ok: true, value: { ProductQuote } } | { ok: false, error: PriceError },
}

export type DiscountLike = { Type: string, Percent: number }

export type ProductInfoLike = {
    PriceInRobux: number?,
    UserBasePriceInRobux: number?,
    PriceDiscountDetails: { DiscountLike }?,
}

export type MarketplaceLike = {
    GetProductInfoAsync: (self: unknown, id: number, infoTypeName: string) -> ProductInfoLike,
    ListDeveloperProducts: (self: unknown) -> { { [string]: unknown } },
}

export type Deps = { marketplace: MarketplaceLike }

local INFO_TYPE_BY_KIND: { [PriceKind]: string } = {
    product = "Product",
    gamePass = "GamePass",
}

local PLUS_DISCOUNT_TYPE = "RobloxPlusSubscription"

local RobloxPriceLookup = {}

local function quoteFromInfo(info: ProductInfoLike): PriceQuote?
    local robux = info.PriceInRobux
    if robux == nil then
        return nil
    end
    local base = info.UserBasePriceInRobux or robux
    local percent = 0
    local plus = false
    local discounts: { DiscountLike } = info.PriceDiscountDetails or {}
    for _, discount in discounts do
        percent += discount.Percent
        plus = plus or discount.Type == PLUS_DISCOUNT_TYPE
    end
    return { robux = robux, baseRobux = base, discountPercent = percent, plusDiscount = plus }
end

function RobloxPriceLookup.new(deps: Deps): PriceLookup
    local lookup: PriceLookup = {
        quote = function(_self: PriceLookup, kind: PriceKind, id: number)
            local loaded, info = pcall(function(): ProductInfoLike
                return deps.marketplace:GetProductInfoAsync(id, INFO_TYPE_BY_KIND[kind])
            end)
            if not loaded then
                return {
                    ok = false,
                    error = {
                        kind = "price_failed",
                        message = `GetProductInfoAsync failed: {tostring(info)}`,
                    },
                }
            end
            local quote = quoteFromInfo(info)
            if quote == nil then
                return {
                    ok = false,
                    error = { kind = "price_failed", message = `item {id} is not for sale` },
                }
            end
            return { ok = true, value = quote }
        end,
        listProducts = function(_self: PriceLookup)
            local loaded, rows = pcall(function(): { { [string]: unknown } }
                return deps.marketplace:ListDeveloperProducts()
            end)
            if not loaded then
                return {
                    ok = false,
                    error = {
                        kind = "price_failed",
                        message = `GetDeveloperProductsAsync failed: {tostring(rows)}`,
                    },
                }
            end
            local products: { ProductQuote } = {}
            for index, row in rows do
                local productId = row.ProductId
                local price = row.PriceInRobux
                if type(productId) ~= "number" or type(price) ~= "number" then
                    return {
                        ok = false,
                        error = {
                            kind = "price_failed",
                            message = `developer product row {index} lacks ProductId or PriceInRobux`,
                        },
                    }
                end
                table.insert(products, {
                    productId = productId,
                    quote = {
                        robux = price,
                        baseRobux = price,
                        discountPercent = 0,
                        plusDiscount = false,
                    },
                })
            end
            return { ok = true, value = products }
        end,
    }
    return lookup
end

return RobloxPriceLookup
