--!strict
--[[
    Pure product delivery (D-38): what each developer product gives the player (coins, or bait).
    Loads under Lune. The grant table comes from Config.developerProducts (see
    `Config.grantsByName`); this module only applies it to player data.

    `apply` either mutates the data or returns a typed error and leaves it untouched, so the
    server `grant` can return true only on success and Monetization never records a failed
    grant (Roblox retries the receipt).
]]

-- Structurally identical to Config.ProductGrant (kept local so this file loads under Lune).
export type ProductGrant =
    { kind: "coins", amount: number }
    | { kind: "bait", amount: number, maxBait: number }

-- The slice of PlayerData that grants write to.
export type GrantTarget = { coins: number, bait: number }

export type GrantError =
    { kind: "unknown_product", productName: string }
    | { kind: "invalid_amount", productName: string, amount: number }
    | { kind: "overflow", productName: string }

export type GrantResult = { ok: true, value: nil } | { ok: false, error: GrantError }

export type ProductGrants = {
    apply: (self: ProductGrants, data: GrantTarget, productName: string) -> GrantResult,
}

local ProductGrantsModule = {}

-- Largest integer a Luau number holds exactly; coins beyond it would silently lose precision.
ProductGrantsModule.MAX_COINS = 2 ^ 53

function ProductGrantsModule.new(grants: { [string]: ProductGrant }): ProductGrants
    local service: ProductGrants = {
        apply = function(_self: ProductGrants, data: GrantTarget, productName: string): GrantResult
            local grant = grants[productName]
            if grant == nil then
                return {
                    ok = false,
                    error = { kind = "unknown_product", productName = productName },
                }
            end
            if grant.kind == "bait" then
                local baitAmount = grant.amount
                if
                    baitAmount ~= baitAmount
                    or baitAmount <= 0
                    or baitAmount % 1 ~= 0
                    or grant.maxBait < 1
                then
                    return {
                        ok = false,
                        error = {
                            kind = "invalid_amount",
                            productName = productName,
                            amount = baitAmount,
                        },
                    }
                end
                -- At the stock cap this is a granted clamp: failing it would make Roblox retry
                -- the receipt forever (ADR 0016, ADR 0021).
                data.bait = math.min(grant.maxBait, data.bait + baitAmount)
                return { ok = true, value = nil }
            end
            local amount = grant.amount
            if
                amount ~= amount
                or amount <= 0
                or amount % 1 ~= 0
                or amount > ProductGrantsModule.MAX_COINS
            then
                return {
                    ok = false,
                    error = { kind = "invalid_amount", productName = productName, amount = amount },
                }
            end
            if data.coins > ProductGrantsModule.MAX_COINS - amount then
                return { ok = false, error = { kind = "overflow", productName = productName } }
            end
            data.coins += amount
            return { ok = true, value = nil }
        end,
    }
    return service
end

return ProductGrantsModule
