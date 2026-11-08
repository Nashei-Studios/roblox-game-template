--!strict
--[[
    Offer rail: which purchase offers a player sees, in which order, and when. Pure: loads under
    Lune; session time, account age, ownership and the rotation index are passed in by the server.

    - Permanent offers show first, then `rotatingSlots` offers taken from the rotating pool
      starting at `rotationIndex` (the index comes from features/liveops Rotation or any clock).
    - Starter timing: `startsAfterSessionSeconds` holds an offer back until the player has played
      that long this session; `maxAccountAgeDays` closes it for veterans.
    - Owned items (passes, one-time products) and items dismissed this session are hidden.
    - The rail NEVER grants: buying goes through the existing purchase path, receipts and
      ProcessReceipt (ADR 0016). `canPrompt` lets the server refuse a prompt for an offer the
      player is not currently shown, so a client cannot ask for a hidden or expired offer.
]]

export type ItemKind = "gamePass" | "product"

export type Offer = {
    -- Stable id the client sends as intent. 1 to 32 characters.
    id: string,
    kind: ItemKind,
    -- Name of an entry of Config.gamePasses or Config.developerProducts. No price here.
    itemName: string,
    rotating: boolean,
    -- Seconds of the current session before the offer appears. 0 = at once.
    startsAfterSessionSeconds: number,
    -- Offer closes when the account is older than this many days. nil = never.
    maxAccountAgeDays: number?,
    -- Hide it once the player owns the item (true for passes and one-time packs).
    hideWhenOwned: boolean,
}

export type OfferRailConfig = {
    maxVisible: number,
    rotatingSlots: number,
    offers: { Offer },
}

export type Context = {
    sessionSeconds: number,
    -- Days since the player first joined this experience.
    accountAgeDays: number,
    owns: (kind: ItemKind, itemName: string) -> boolean,
    dismissed: { [string]: boolean },
    -- Moves the rotating window; any non-negative integer.
    rotationIndex: number,
}

local OfferRailModule = {}

--- One human-readable problem per invalid value (empty when valid). `passes` and `products` are
--- the sets of names in Config.
function OfferRailModule.validate(
    config: OfferRailConfig,
    passes: { [string]: boolean },
    products: { [string]: boolean }
): { string }
    local problems: { string } = {}
    if config.maxVisible < 1 or config.maxVisible % 1 ~= 0 then
        table.insert(problems, "offerRail.maxVisible must be a positive integer")
    end
    if config.rotatingSlots < 0 or config.rotatingSlots % 1 ~= 0 then
        table.insert(problems, "offerRail.rotatingSlots must be zero or a positive integer")
    end
    local seen: { [string]: boolean } = {}
    for _, offer in config.offers do
        if offer.id == "" or #offer.id > 32 then
            table.insert(problems, "an offer id must be 1 to 32 characters")
        end
        if seen[offer.id] then
            table.insert(problems, `offer "{offer.id}" is declared twice`)
        end
        seen[offer.id] = true
        local known = if offer.kind == "gamePass" then passes else products
        if not known[offer.itemName] then
            table.insert(problems, `offer "{offer.id}" names an unknown item "{offer.itemName}"`)
        end
        if offer.startsAfterSessionSeconds < 0 then
            table.insert(problems, `offer "{offer.id}" has a negative start delay`)
        end
        local maxAge = offer.maxAccountAgeDays
        if maxAge ~= nil and maxAge < 0 then
            table.insert(problems, `offer "{offer.id}" has a negative account age limit`)
        end
    end
    return problems
end

local function eligible(offer: Offer, context: Context): boolean
    if context.dismissed[offer.id] then
        return false
    end
    if context.sessionSeconds < offer.startsAfterSessionSeconds then
        return false
    end
    local maxAge = offer.maxAccountAgeDays
    if maxAge ~= nil and context.accountAgeDays > maxAge then
        return false
    end
    if offer.hideWhenOwned and context.owns(offer.kind, offer.itemName) then
        return false
    end
    return true
end

--- The offers to show, in order, at most `maxVisible`.
function OfferRailModule.visible(config: OfferRailConfig, context: Context): { Offer }
    local shown: { Offer } = {}
    local pool: { Offer } = {}
    for _, offer in config.offers do
        if offer.rotating then
            if eligible(offer, context) then
                table.insert(pool, offer)
            end
        elseif eligible(offer, context) and #shown < config.maxVisible then
            table.insert(shown, offer)
        end
    end
    local take = math.min(config.rotatingSlots, #pool, config.maxVisible - #shown)
    for step = 0, take - 1 do
        table.insert(shown, pool[(context.rotationIndex + step) % #pool + 1])
    end
    return shown
end

--- True when `offerId` is among the offers the player is shown right now.
function OfferRailModule.canPrompt(
    config: OfferRailConfig,
    context: Context,
    offerId: string
): Offer?
    for _, offer in OfferRailModule.visible(config, context) do
        if offer.id == offerId then
            return offer
        end
    end
    return nil
end

return OfferRailModule
