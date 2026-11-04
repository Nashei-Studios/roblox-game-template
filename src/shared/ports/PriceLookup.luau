--!strict
--[[
    Port: live Robux prices (ADR 0022). Every price a UI shows comes from here, read at runtime
    from the platform, because Roblox Plus subscribers see a 10 to 20 percent discount and a
    hardcoded number would show them the wrong price (docs: production/monetization/roblox-plus).
    Config holds no display prices.
]]

export type PriceKind = "product" | "gamePass"

export type PriceQuote = {
    -- What this player pays now (PriceInRobux).
    robux: number,
    -- The price before any discount (UserBasePriceInRobux).
    baseRobux: number,
    -- Total discount percent applied to this player, 0 when none.
    discountPercent: number,
    -- True when part of the discount comes from Roblox Plus.
    plusDiscount: boolean,
}

export type ProductQuote = { productId: number, quote: PriceQuote }

export type PriceError = { kind: "price_failed", message: string }

export type PriceLookup = {
    -- GetProductInfoAsync for one developer product or game pass.
    quote: (
        self: PriceLookup,
        kind: PriceKind,
        id: number
    ) -> { ok: true, value: PriceQuote } | { ok: false, error: PriceError },
    -- GetDeveloperProductsAsync: every developer product of the experience.
    listProducts: (
        self: PriceLookup
    ) -> { ok: true, value: { ProductQuote } } | { ok: false, error: PriceError },
}

return {}
